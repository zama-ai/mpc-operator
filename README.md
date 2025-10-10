# Zama MPC Operator Kubernetes Deployment

This repo contains example Helm chart configuration to deploy a Zama MPC party on EKS, including:

* KMS-core
* Gateway Arbitrum Full node
* KMS-Connector

## Requirements

* EKS cluster following base requirements
* [Zama MPC Cluster Terraform Modules](https://github.com/zama-ai/terraform-mpc-modules)
    * mpc-party
    * vpc-endpoint-provider
    * vpc-endpoint-consumer

## Charts

* [MPC Operator Check](./)