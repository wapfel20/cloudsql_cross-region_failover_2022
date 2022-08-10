# cloudsql_cross-region_failover_2022
Automating cross-region failures in Google Cloud SQL with HA and Cascading Replicas

This project covers the automation of conducting a cross region failover in Google Cloud SQL. 

Assumptions
Before running this playbook, please confirm you have the following architecture components in place:
- You are using a High Availability Cloud SQL instance as your Primary Instance.
- You have at least one Read Replica in a different GCP Region than your Primary Instance, and that <a href="https://cloud.google.com/sql/docs/mysql/high-availability#read_replicas">Read Replica is configured for High Availability</a>. Without having a read replica in a different GCP region provisioned prior to an incident, the failover process as automated in this playbook is not possible.
- If you have additional Read Replicas serving read-only applications, those replicas are using Cascading Replication so they are not dependent on the Primary Instance for Replication.

Example Architecture
<insert diagram>

What does the script do?
- This script automates the process of failing a Cloud SQL instance over to a different GCP Region during a regional outage event. To accomplish this, the script automates the following based on user input:
  - Selecting the right GCP project that the instance resides in (user input)
  - Capturing the primary ID of the Instance that's down (user input)
  - Caputuring the ID of the DR read replica you want to fail over to (user input)
  - Promoting the DR instance in the new region to a primary writable cloud sql instance
  - Upgrading the DR instance to be HA enabled and sets backups and other settigns to be consistent with the original primary instance
  - Replacing the original primary instance with a read replica in the same zone
  - Identifyiung any other replicas from the original primary and then replaces them with new replicas
  - Providing connection details for all newly provisioned instances and replicas
  - Optional: Deleting the old primary instance and replicas. To use this feature, use sqlFailover.sh script. If you want to manually cleanup the instances, use the sqlFailoverSansDeletions.sh script.
  
  Failing back to your Primary Region
  - You can use this script to conduct a controlled failover back to your orginal Region and Zone prior to a regional outage. Just re-run the script and use the DR instance (now the primary running in a separate region) and the replacement replica in the orignal location as the target. It will promote the replica, update, patch, and configure it to be HA, replace any replicas, and replace the DR primary instance with a replica in the same region... making it ready once again for a regional outage.
  
  Migration vs Disaster Recovery
  - This script was designed with Disaster Recovery in mind but a planned "Regional Migration" is no different. It can be used for this scenario as well.
  
  Using the script via Cloud Shell
  - To use this script via cloud shell or any other shell:
    - In the Google Cloud Console (console.google.com) or on your own device, open a terminal window
    - clone the repository into your working directory
    - Run one of the scripts (standard or no delete) using "bash" - ex. bash sqlFailover.sh
    - Look for prompts and instructions in the terminal. It will guide you through the failover process.
