locals {
  ssh_pub_key_path  = "./key.pub"
  ssh_priv_key_path = "./key"
}

locals {
  ssh_pub_key_content = file(local.ssh_pub_key_path)
}
