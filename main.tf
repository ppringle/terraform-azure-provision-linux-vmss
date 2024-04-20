locals {
  required_tags = {
    DeploymentMethod = "terraform"
    Environment      = var.environment
    ProjectName      = var.project_name
  }
}

data azurerm_subscription "current" {}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${var.resource_location}-01"
  location = var.resource_location
  tags     = local.required_tags
}

resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}

resource "azurerm_virtual_network" "main" {
  name                = "vmss-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.resource_location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.required_tags
}

resource "azurerm_subnet" "vmss" {
  name                 = "vmss-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  depends_on           = [azurerm_virtual_network.main]
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "vmss" {
  name                = "vmss-public-ip"
  location            = var.resource_location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  domain_name_label   = random_string.fqdn.result
  tags                = local.required_tags
}

resource "azurerm_lb" "vmss" {
  name                = "vmss-lb"
  location            = var.resource_location
  resource_group_name = azurerm_resource_group.main.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vmss.id
  }

  tags = local.required_tags
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  loadbalancer_id = azurerm_lb.vmss.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
  loadbalancer_id = azurerm_lb.vmss.id
  name            = "ssh-running-probe"
  port            = var.application_port
}

resource "azurerm_lb_rule" "lbnatrule" {
  loadbalancer_id                = azurerm_lb.vmss.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = var.application_port
  backend_port                   = var.application_port
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpepool.id]
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.vmss.id
}

resource "azurerm_user_assigned_identity" "main" {
  name                = "uai-${var.project_name}-${var.environment}-${var.resource_location}-01"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.required_tags
}

resource "azurerm_role_assignment" "vmss_level_permissions" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}


resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                            = "vmss-${var.project_name}-${var.environment}-${var.resource_location}-01"
  location                        = var.resource_location
  resource_group_name             = azurerm_resource_group.main.name
  sku                             = var.vm_image_size
  instances                       = 1
  admin_username                  = var.username
  admin_password                  = var.password
  disable_password_authentication = false
  custom_data                     = base64encode(file("scripts/cloud-init-config.yml"))
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "terraform-network-profile"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.vmss.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
    }

  }
  tags = local.required_tags
}

resource "azurerm_public_ip" "jumpbox" {
  name                = "jumpbox-public-ip"
  location            = var.resource_location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  domain_name_label   = "${random_string.fqdn.result}-ssh"
  tags                = local.required_tags
}

resource "azurerm_network_interface" "jumpbox" {
  name                = "jumpbox-nic"
  location            = var.resource_location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "IPConfiguration"
    subnet_id                     = azurerm_subnet.vmss.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jumpbox.id
  }

  tags = local.required_tags
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                  = "vm-${var.project_name}-${var.environment}-${var.resource_location}-01"
  location              = var.resource_location
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = [azurerm_network_interface.jumpbox.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    name                 = "vmss-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  admin_username = var.username
  computer_name  = "jumpbox"
  size           = var.vm_image_size

  tags = local.required_tags
}
