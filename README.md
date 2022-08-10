# cloudsql_cross-region_failover_2022
Automating cross-region failures in Google Cloud SQL with HA and Cascading Replicas

This project covers the automation of conducting a cross region failover in Google Cloud SQL using HA Replicas and Cascading Replicas. If you are not suing these features, please see my <a href="https://github.com/wapfel20/cloudsql_cross-region_failover">original script using standard replicas</a>.

<h3>Assumptions</h3>

Before running this playbook, please confirm you have the following architecture components in place:
- You are using a High Availability Cloud SQL instance as your Primary Instance.
- You have at least one Read Replica in a different GCP Region than your Primary Instance, and that <a href="https://cloud.google.com/sql/docs/mysql/high-availability#read_replicas">Read Replica is configured for High Availability</a>. Without having a read replica in a different GCP region provisioned prior to an incident, the failover process as automated in this playbook is not possible.
- If you have additional Read Replicas serving read-only applications, those replicas are using Cascading Replication so they are not dependent on the Primary Instance for Replication.

<h3>Example Architecture</h3>
<img alt="PNG" src="https://github.com/wapfel20/cloudsql_cross-region_failover_2022/blob/main/ExampleArchitecture.png" />

<h3>What does this script do?</h3>
This script automates the process of failing a Cloud SQL instance over to a different GCP Region during a regional outage event. To accomplish this, the script automates the following based on user input:
 -1. Selecting the right GCP project that the instance resides in (user input)
 -2. Capturing the Instance ID of the Primary Instance in the region that is down (user input)
 -3. Capturing the Instance ID of the DR Read Replica that you want to fail over to (user input)
 -4. Facilitating the failover by promoting the DR Instance in the new region to the primary writable cloud sql instance
 -5. Providing connection details for the newly promoted Instance
 -6. Replacing the original Primary Instance with an HA Read Replica in the same zone for future failback procedures
  
<h3>Failing back to your Primary Region</h3>
  - You can use the automated_post-DR_sql_failback script to conduct a controlled failover back to the orginal Region and Zone you used prior to the regional outage. This script will complete a very similar process to the one specified above, but it will leverage the HA Read Replica created in step #6 as the failover target, and will entail fully replacing any and all replicas.
  
<h3>Migration vs Disaster Recovery</h3>
  - This script was designed with Disaster Recovery in mind but a planned "Regional Migration" is no different. It can be used for this scenario as well.
  
<h3>Using the script via Cloud Shell</h3>
  - To use this script via cloud shell or any other shell:
    - In the Google Cloud Console (console.google.com) or on your own device, open a terminal window
    - clone the repository into your working directory
    - Run one of the scripts (standard or no delete) using "bash" - ex. bash sqlFailover.sh
    - Look for prompts and instructions in the terminal. It will guide you through the failover process.
