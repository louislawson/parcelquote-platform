# Named terraform.tf, not providers.tf as the two root configurations call their equivalent,
# and the difference is the point: a module must not declare a provider block, because the
# caller cannot override one and a module carrying its own breaks destroy ordering later. The
# roots merge the two concerns into one file because they do configure a provider; here there
# is nothing to merge, so the name HashiCorp's style guide and the Azure Verified Modules spec
# both give this file is the right one.
terraform {
  required_version = ">= 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.3"
    }
  }
}
