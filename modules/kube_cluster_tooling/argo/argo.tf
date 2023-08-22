###############################################
## Providers ##
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.22.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.10.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
  }
}

###############################################
## Variables ##

variable "dns_domain" {
  description = "The DNS domain to be used for the setup."
  type        = string
}

variable "ingress_class_name" {
  description = "The Ingress Class Name."
  type        = string
}

variable "argo_cd_chart_version" {
  description = "The version of the Argo CD to be deployed."
  type        = string
}

variable "email" {
  description = "The email for letsencrypt setup."
  type        = string
}

variable "argo_workflows_chart_version" {
  description = "The version of the Argo Workflows to be deployed."
  type        = string
}

variable "argo_workflows_ingress_enabled" {
  description = "The version of the Argo Workflows to be deployed."
  type        = bool
  default     = false
}

variable "argo_events_chart_version" {
  description = "The version of the Argo Events to be deployed."
  type        = string
}

variable "kube_config_file" {
  description = "Path to kubeconfig file"
  type        = string
}




##############################################
## ArgoCD ##

// argo-cd
resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argo_cd_chart_version

  namespace        = "argocd"
  create_namespace = true

  values = [<<EOF
configs:
  cm:
    data:
      rbac.defaultPolicy: role:admin
      rbac.policy.csv: |
        p, role:admin, applications, *, */*
        g, admin, role:admin
    exec.enabled: false
    url: "https://argocd.${var.dns_domain}"
  params:
    server.insecure: true

server:
  certificate:
    domain: "argocd.${var.dns_domain}"
  resources:
    limits:
      cpu: 1000m
      memory: 2Gi
    requests:
      cpu: 1000m
      memory: 1Gi
  ingress:
    enabled: true
    hosts:
      - argocd.${var.dns_domain}
    servicePort: 80
    annotations:
      traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt-production
      kubernetes.io/ssl-passthrough: "true"
    tls:
      - hosts:
        - argocd.${var.dns_domain}
        secretName: "argocd-secret"
EOF
  ]

}

// argo-workflows
resource "helm_release" "argo_workflows" {
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = var.argo_workflows_chart_version

  namespace        = "argocd"
  create_namespace = false

  values = [local.argo_workflows_values]

  depends_on = [
    helm_release.argo_cd,
  ]
}

locals {
  argo_workflows_values = <<YAML
server:
  extraArgs:
  - --auth-mode=server
  ingress:
    annotations:
      traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt-production
      kubernetes.io/ssl-passthrough: "true"
    enabled: ${var.argo_workflows_ingress_enabled}
    hosts:
    - argo-workflows.${var.dns_domain}
    servicePort: 80
    tls:
    - hosts:
      - argo-workflows.${var.dns_domain}
      secretName: "tls-argo-workflows-cert"
YAML
}

// argo-events
resource "helm_release" "argo_events" {
  name       = "argo-events"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-events"
  version    = var.argo_events_chart_version

  namespace        = "argocd"
  create_namespace = false

  set {
    name  = "crds.install"
    value = "true"
  }

  depends_on = [
    helm_release.argo_cd,
  ]

}

resource "kubectl_manifest" "argo_eventbus" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
spec:
  nats:
    native:
      # Optional, defaults to 3. If it is < 3, set it to 3, that is the minimal requirement.
      replicas: 3
      # Optional, authen strategy, "none" or "token", defaults to "none"
      auth: token
#      containerTemplate:
#        resources:
#          requests:
#            cpu: "10m"
#      metricsContainerTemplate:
#        resources:
#          requests:
#            cpu: "10m"
#      antiAffinity: false
#      persistence:
#        storageClassName: standard
#        accessMode: ReadWriteOnce
#        volumeSize: 10Gi
YAML
  depends_on = [
    helm_release.argo_events,
  ]
}
