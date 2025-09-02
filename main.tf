terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.34.0"
    }
  }
  # backend "azurerm" {
  #   resource_group_name  = ""
  #   storage_account_name = ""
  #   container_name       = ""
  #   key                  = ""
  # }
}

provider "azurerm" {

  features {}
  subscription_id = "b23d929c-5d14-4285-a3cd-840ec9c55cde"
}
resource "azurerm_resource_group" "rgblock" {
  name     = "my_rg1"
  location = "west us"
}

resource "azurerm_virtual_network" "vnetblock" {
  name                = "my_vnet"
  location            = "west us"
  resource_group_name = azurerm_resource_group.rgblock.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnetblock" {
  count                = 3
  name                 = "subnet${count.index}"
  resource_group_name  = azurerm_resource_group.rgblock.name
  address_prefixes     = ["10.0.${count.index}.0/24"]
  virtual_network_name = azurerm_virtual_network.vnetblock.name
}

resource "azurerm_public_ip" "publicip" {
  name                = "my_public_ip"
  location            = azurerm_resource_group.rgblock.location
  resource_group_name = azurerm_resource_group.rgblock.name
  allocation_method   = "Static"
  sku= "Standard"
}

resource "azurerm_lb" "lbblock" {
  name                = "my_lb"
  location            = azurerm_resource_group.rgblock.location
  resource_group_name = azurerm_resource_group.rgblock.name

  frontend_ip_configuration {
    name                 = "my_frontend"
    public_ip_address_id = azurerm_public_ip.publicip.id
    # subnet_id =azurerm_subnet.subnetblock[1].id
    # private_ip_address = "Static"

  }
}
resource "azurerm_lb_backend_address_pool" "bkndpool" {
  name            = "BackEndAddressPool"
  loadbalancer_id = azurerm_lb.lbblock.id
}
resource "azurerm_lb_probe" "http_probe" {
  name                = "http-probe"
  loadbalancer_id     = azurerm_lb.lbblock.id
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http_rule" {
  name                           = "http-rule"
  loadbalancer_id                = azurerm_lb.lbblock.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "my_frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bkndpool.id]
  probe_id                       = azurerm_lb_probe.http_probe.id
}

# 9. Network Security Group (Allow HTTP)
resource "azurerm_network_security_group" "nsg" {
  name                = "allow-http"
  location            = azurerm_resource_group.rgblock.location
  resource_group_name = azurerm_resource_group.rgblock.name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# 10. NICs + VMs (2 instances)
resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "nic-${count.index}"
  location            = azurerm_resource_group.rgblock.location
  resource_group_name = azurerm_resource_group.rgblock.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnetblock[count.index].id
    private_ip_address_allocation = "Dynamic"
   
  
    
  }

}
resource "azurerm_network_interface_backend_address_pool_association" "nic_backend_assoc" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "internal"  # Must match NIC ip_configuration name
  backend_address_pool_id = azurerm_lb_backend_address_pool.bkndpool.id
}


resource "azurerm_linux_virtual_machine" "vm" {
  count               = 2
  name                = "vm-${count.index}"
  resource_group_name = azurerm_resource_group.rgblock.name
  location            = azurerm_resource_group.rgblock.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id
  ]
  admin_password                  = "P@ssw0rd1234!" # For testing only; use SSH in production
  disable_password_authentication = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-${count.index}"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  

  tags = {
    environment = "demo"
  }
}

# 11. Output Public IP
output "load_balancer_public_ip" {
  value = azurerm_public_ip.publicip.ip_address
}