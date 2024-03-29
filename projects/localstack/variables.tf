variable "project_name" {
    type = string
    description = "Name of the example project"

    default = "telemetry-service"
}

variable "instance_type" {
    type = string
    description = "EC2 instance type for Grafana"

    default = "t2.micro"
}

variable "function_path" {
    type = string
    description = "File path to lambda sources"

    default = "../../functions"
}

variable "region" {}
variable "key_pair_name" {}
variable "public_key_path" {}
variable "private_key_path" {}
variable "influx_admin_pw" {}
variable "influx_user_pw" {}
variable "grafana_admin_pw" {}
variable "grafana_user_pw" {}

# for testing
variable "influxdb_token" { default = "my-super-secret-auth-token" }
