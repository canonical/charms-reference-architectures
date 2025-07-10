# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  JUJU_K8S_APPS       = "juju-k8s-apps"
  juju_k8s_apps_steps = [
    {
      name    = "UpdateAndInstallPackages"
      script  = "scripts/juju-k8s-apps/ami-install-packages.sh"
    },
    {
      name    = "SetupMicrok8s"
      script  = "scripts/juju-k8s-apps/ami-setup-microk8s.sh"
    }
  ]
}

resource "aws_imagebuilder_component" "juju_k8s_apps_component" {
  name        = "${local.JUJU_K8S_APPS}-component"
  description = "The build component of the image."
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "setup-${local.JUJU_K8S_APPS}-env"
    description   = "Install dependencies and setup the juju-k8s-apps environment."
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
                  "aws s3 cp s3://${aws_s3_bucket.imagebuilder_scripts_bucket.bucket}/scripts/${local.JUJU_K8S_APPS}/ /tmp/ --recursive"
                ]
              }
            },
          ],
          [
            for step in local.juju_k8s_apps_steps : {
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

resource "aws_imagebuilder_image_recipe" "juju_k8s_apps_image_recipe" {
  name         = "${local.JUJU_K8S_APPS}-image-recipe"
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
    component_arn = aws_imagebuilder_component.juju_k8s_apps_component.arn
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "juju_k8s_apps_infra_config" {
  name                          = "${local.JUJU_K8S_APPS}-infra-config"
  instance_profile_name         = aws_iam_instance_profile.imagebuilder_profile.name
  terminate_instance_on_failure = true
  instance_types                = ["t3.medium"]
}

resource "aws_imagebuilder_image_pipeline" "juju_k8s_apps_pipeline" {
  name                             = "${local.JUJU_K8S_APPS}-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.juju_k8s_apps_image_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.juju_k8s_apps_infra_config.arn
}

resource "aws_imagebuilder_distribution_configuration" "juju_k8s_apps_dist_config" {
  name = "${local.JUJU_K8S_APPS}-image-distribution"

  distribution {
    region = var.region

    ami_distribution_configuration {
      name        = "${local.JUJU_K8S_APPS}-{{ imagebuilder:buildDate }}"
      description = "AMI of juju-k8s-apps units for air-gapped deployments."
    }
  }
}

resource "aws_imagebuilder_image" "juju_k8s_apps_image" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.juju_k8s_apps_image_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.juju_k8s_apps_infra_config.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.juju_k8s_apps_dist_config.arn
}
