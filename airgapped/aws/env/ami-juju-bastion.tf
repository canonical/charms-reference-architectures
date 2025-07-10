# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  BASTION  = "bastion"
  bastion_steps = [
    {
      name    = "UpdateAndInstallPackages"
      script  = "scripts/bastion/ami-install-packages.sh"
    },
    {
      name    = "SetupJujuConfig"
      script  = "scripts/bastion/ami-setup-juju.sh"
    }
  ]
}

resource "aws_imagebuilder_component" "bastion_component" {
  name        = "${local.BASTION}-component"
  description = "The build component of the image."
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "setup-${local.BASTION}-env"
    description   = "Install dependencies and setup the bastion environment."
    schemaVersion = "1.0"
    phases = [
      {
        name  = "build"
        steps = concat(
          [
            {
              name      = "DownloadScriptsAndResourcesFromS3"
              action    = "ExecuteBash"
              onFailure = "Abort"
              inputs = {
                commands = [
                  "snap install aws-cli --classic",
                  "aws s3 cp s3://${aws_s3_bucket.imagebuilder_scripts_bucket.bucket}/scripts/${local.BASTION}/ /tmp/ --recursive"
                ]
              }
            },
          ],
          [
            for step in local.bastion_steps : {
              name      = step.name
              action    = "ExecuteBash"
              onFailure = "Abort"
              inputs = {
                commands = [
                  "chmod +x /tmp/${basename(step.script)} && bash /tmp/${basename(step.script)}"
                ]
              }
            }
          ]
        )
      }
    ]
  })

  depends_on = [
    aws_s3_object.imagebuilder_scripts
  ]
}

resource "aws_imagebuilder_image_recipe" "bastion_image_recipe" {
  name         = "${local.BASTION}-image-recipe"
  version      = "1.0.0"
  parent_image = "arn:aws:imagebuilder:${var.region}:aws:image/ubuntu-server-22-lts-x86/x.x.x"
  # Use the latest Ubuntu AMI

  block_device_mapping {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 75
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  component {
    component_arn = aws_imagebuilder_component.bastion_component.arn
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "bastion_infra_config" {
  name                          = "${local.BASTION}-infra-config"
  instance_profile_name         = aws_iam_instance_profile.imagebuilder_profile.name
  terminate_instance_on_failure = true
  instance_types                = ["t3.medium"]
}

resource "aws_imagebuilder_image_pipeline" "bastion_pipeline" {
  name                             = "${local.BASTION}-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.bastion_image_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.bastion_infra_config.arn
}

resource "aws_imagebuilder_distribution_configuration" "bastion_dist_config" {
  name = "${local.BASTION}-image-distribution"

  distribution {
    region = var.region

    ami_distribution_configuration {
      name        = "${local.BASTION}-{{ imagebuilder:buildDate }}"
      description = "AMI of bastion units for air-gapped deployments."
    }
  }
}

resource "aws_imagebuilder_image" "bastion_image" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.bastion_image_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.bastion_infra_config.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.bastion_dist_config.arn
}
