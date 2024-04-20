variable "application_port" {
  description = "Port that you want to expose to the external load balancer"
  default     = 80
}

variable "project_name" {
  type = string
  default = "ppringle-terraform-demo"
}

variable "environment" {
  type = string
  default = "dev"
}

variable "resource_location" {
  type = string
  default = "canadacentral"
}

variable "username" {
  type = string
  default = "azureuser"
}

variable "password" {
  type = string
  default = "azureuser123!"
}

variable "vm_image_size" {
  type = string
  default = "Standard_DS1_v2"
}