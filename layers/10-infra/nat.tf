module "fck_nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "1.6.1"

  name      = "${var.project}-nat"
  region    = var.region
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]

  ha_mode             = true
  instance_type       = "t4g.nano"
  use_spot_instances  = false
  update_route_tables = true
  route_tables_ids = {
    az_a = module.vpc.private_route_table_ids[0]
    az_b = module.vpc.private_route_table_ids[1]
  }
}