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
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = var.az_subscription_id
  features {}
}
