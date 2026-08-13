# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "model_uuid" {
  description = "UUID of the LDAP Kubernetes model."
  value       = juju_model.ldap.uuid
}

output "components" {
  description = "Components deployed in the LDAP model."
  value = {
    self_signed_certificates = module.self_signed_certificates
    glauth                   = module.glauth
    glauth_utils             = juju_application.glauth_utils
    traefik                  = module.traefik
    postgresql               = module.postgresql
  }
}

output "offers" {
  description = "Cross-model offers exposed by the LDAP deployment."
  value = {
    certificates = { url = module.self_signed_certificates.offers["certificates"].url }
    ldap         = { url = juju_offer.ldap.url }
    send_ca_cert = { url = juju_offer.send_ca_cert.url }
  }
}
