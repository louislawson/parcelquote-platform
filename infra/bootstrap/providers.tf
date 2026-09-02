terraform {
  required_version = ">= 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.3"
    }
  }
}

provider "azurerm" {
  subscription_id = var.az_subscription_id
  features {}
}
