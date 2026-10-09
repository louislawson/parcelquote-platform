# Re-exported from the module rather than dropped. The deploy stage reads app_fqdn and
# candidate_fqdn with terraform output, so removing these would apply cleanly and then fail
# afterwards, which is the worst order to find out. A module output with no passthrough here is
# the same bug the other way round: it exists, and nothing outside Terraform can read it.
#
# The descriptions are duplicated from the module, which is a real cost: the module's wording
# was corrected once and these were missed, so both READMEs documented an output the pipeline
# had stopped using. There is no way to inherit a description, so they have to be kept in step
# by hand.
output "app_fqdn" {
  description = "Stable hostname, serving whichever revisions the traffic weights point at."
  value       = module.workload.app_fqdn
}

output "candidate_fqdn" {
  description = "Hostname of the green-labelled revision, reachable whatever share of traffic that revision carries, which is what allows a new revision to be verified before any traffic reaches it. Null in Single mode, where there is no label."
  value       = module.workload.candidate_fqdn
}

output "latest_revision_fqdn" {
  description = "Hostname of the newest revision as the provider last read it, for reading by hand. Stale by one revision immediately after an apply, so nothing automated should assert against it."
  value       = module.workload.latest_revision_fqdn
}

output "latest_revision_name" {
  description = "Name of the newest revision as the provider last read it, for correlating container logs by hand. Stale by one revision immediately after an apply, for the same reason as above."
  value       = module.workload.latest_revision_name
}
