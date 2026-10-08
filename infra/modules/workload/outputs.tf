output "app_fqdn" {
  description = "Stable hostname, serving whichever revisions the traffic weights point at."
  value       = one(azurerm_container_app.ca.ingress).fqdn
}

# Built from the app name and the environment's domain rather than from any revision attribute,
# and that is the whole point: both are stable across deployments, so this never reads the
# provider's latest_revision_fqdn, which is one revision behind immediately after an apply. Three
# dashes, not two — a label name may not contain two consecutive dashes, so Azure separates the
# label from the app name with a third.
#
# Null rather than a string in Single mode, where no traffic weight carries a label and this
# hostname would not resolve. A caller health-checking a 404 would be proving nothing, and an
# empty output fails louder than a wrong one.
output "candidate_fqdn" {
  description = "Hostname of the green-labelled revision, reachable whatever share of traffic that revision carries, which is what allows a new revision to be verified before any traffic reaches it. Null in Single mode, where there is no label."
  value = var.revision_mode == "Multiple" ? format(
    "%s---green.%s",
    azurerm_container_app.ca.name,
    azurerm_container_app_environment.cae_env.default_domain,
  ) : null
}

# Deliberately not consumed by anything. It was written in phase 2 expecting the smoke test to
# use it, which that test never did — it polls the stable hostname instead — and the provider has
# since made it unusable for the purpose: both this and latest_revision_name are one revision
# behind immediately after an apply, because the read-back happens before Container Apps has
# registered the new revision. Anything verifying a revision wants candidate_fqdn above, which is
# built rather than read. Kept because it is useful to a person reading state by hand.
output "latest_revision_fqdn" {
  description = "Hostname of the newest revision as the provider last read it, for reading by hand. Stale by one revision immediately after an apply, so nothing automated should assert against it."
  value       = azurerm_container_app.ca.latest_revision_fqdn
}

output "latest_revision_name" {
  description = "Name of the newest revision as the provider last read it, for correlating container logs by hand. Stale by one revision immediately after an apply, for the same reason as above."
  value       = azurerm_container_app.ca.latest_revision_name
}
