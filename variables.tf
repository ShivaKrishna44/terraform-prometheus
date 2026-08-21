variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "keys/my-new-key.pub"
}
