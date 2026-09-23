terraform {
  required_version = ">= 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.3"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-parcelquote-tfstate-uks-01"
    storage_account_name = "stparcelquotetfstuks01"
    container_name       = "tfstate-dev"
    key                  = "dev.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  # Subscription comes from ARM_SUBSCRIPTION_ID, which the pipeline sets from its
  # service connection, or otherwise from the Azure CLI's default subscription.
  features {}
}
