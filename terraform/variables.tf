variable "subscription_id" {
  description = "Azure subscription to deploy into (set in terraform.tfvars, which is gitignored)"
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group that holds everything in this lab"
  type        = string
  default     = "BSpikes-RG"
}

variable "ssh_key_name" {
  description = "Name of the existing SSH public key resource in the resource group"
  type        = string
  default     = "key-lab02"
}

variable "admin_username" {
  description = "Linux admin user on both VMs"
  type        = string
  default     = "azureuser"
}

variable "vm_size" {
  description = "VM size for both servers"
  type        = string
  default     = "Standard_B1s"
}

variable "db_allow_web" {
  description = "true = web subnet may reach the DB. Set false to run the negative test."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    lab   = "lab02"
    owner = "bspikes"
  }
}
