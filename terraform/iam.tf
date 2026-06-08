# AWS Academy Learner Lab does not allow creating IAM roles
# Use the pre-existing LabRole provided by the lab environment

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}