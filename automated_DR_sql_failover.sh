#!/bin/bash

#Set project variables
gcloud auth login
read -p 'Please provide Project ID for the project that your instance is located in:' project
gcloud config set project $project

#Make a temp directory and file to store the JSON output from Gcloud
mkdir tempFiles
touch tempFiles/instanceDetails.json
touch tempFiles/instanceDetails-dr.json
touch tempFiles/primaryReplacementReplica.json

#Prompt the user for the primary instance and target failover replica
read -p 'Enter the Instance ID of the current primary Instance: ' primaryInstance
read -p 'Enter the Instance ID of the HA replica you would like to failover to: ' drInstance

#Pull all data from primary instance needed for scripting
echo "Pulling Data from your SQL instances..."
echo $(gcloud sql instances describe $primaryInstance --format="json") > tempFiles/instanceDetails.json
echo $(gcloud sql instances describe $drInstance --format="json") > tempFiles/instanceDetails-dr.json

#Store Primary instance variables locally
primaryRegion=$(jq '.region' tempFiles/instanceDetails.json)
pRegion=$(echo $primaryRegion | sed 's/^"\(.*\)"$/\1/')
primaryZone=$(jq '.gceZone' tempFiles/instanceDetails.json)
pZone=$(echo $primaryZone | sed 's/^"\(.*\)"$/\1/')
primaryName=$(jq '.name' tempFiles/instanceDetails.json)
primaryTier=$(jq '.settings.tier' tempFiles/instanceDetails.json)
primaryDataDiskSizeGb=$(jq '.settings.dataDiskSizeGb' tempFiles/instanceDetails.json)
primaryDataDiskType=$(jq '.settings.dataDiskType' tempFiles/instanceDetails.json)
primaryNetwork=$(jq '.settings.ipConfiguration.privateNetwork' tempFiles/instanceDetails.json)
primaryNetwork=$(echo ${primaryNetwork##*/})
primaryNetwork=$(echo ${primaryNetwork::-1})
maintenanceWindowDay=$(jq '.settings.maintenanceWindow.day' tempFiles/instanceDetails.json)
maintenanceWindowHour=$(jq '.settings.maintenanceWindow.hour' tempFiles/instanceDetails.json)
primaryIP=$(jq '.ipAddresses' tempFiles/instanceDetails.json)
backupHours=$(jq '.settings.backupConfiguration.startTime' tempFiles/instanceDetails.json | cut -c2-3)
backupMinutes=$(jq '.settings.backupConfiguration.startTime' tempFiles/instanceDetails.json | cut -c5-6)
backupStartTime="$backupHours:$backupMinutes"

#Translate Maintenance Window Day into SUN, MON, TUE, WED, THU, FRI, SAT
if [ "$maintenanceWindowDay" = "1" ]
then
    maintenanceWindowDay="MON"
else
    if [ "$maintenanceWindowDay" = "2" ]
    then
        maintenanceWindowDay="TUE"
    else
        if [ "$maintenanceWindowDay" = "3" ]
        then
            maintenanceWindowDay="WED" 
        else
            if [ "$maintenanceWindowDay" = "4" ]
            then
                maintenanceWindowDay="THU"
            else
                if [ "$maintenanceWindowDay" = "5" ]
                then
                    maintenanceWindowDay="FRI"
                else
                    if [ "$maintenanceWindowDay" = "6" ]
                    then
                        maintenanceWindowDay="SAT"
                    else
                        if [ "$maintenanceWindowDay" = "7" ]
                        then
                            maintenanceWindowDay="SUN"
                        else
                            echo "Not a valid maintenance window variable"
                        fi
                    fi
                fi 
            fi
        fi
    fi
fi

#generate random string for naming
randomid=$(echo $RANDOM | md5sum | head -c 5; echo;)

#Store DR instance variables locally
drRegion=$(jq '.region' tempFiles/instanceDetails-dr.json)
drZone=$(jq '.zone' tempFiles/instanceDetails-dr.json)
drConnectionString=$(jq '.connectionName' tempFiles/instanceDetails-dr.json)
drIP=$(jq '.ipAddresses' tempFiles/instanceDetails-dr.json)
drName=$(jq '.name' tempFiles/instanceDetails-dr.json)
drNameNoQuotes=$(echo $drName| sed 's/^"\(.*\)"$/\1/')
primaryNameNoQuotes=$(echo $primaryName | sed 's/^"\(.*\)"$/\1/')
primaryFailoverReplica=$primaryNameNoQuotes-$randomid

echo "Data pull complete."

#ask user to confirm the action since it is irreversable
echo "You are attempting to failover from $primaryInstance in $primaryRegion to $drInstance in $drRegion."
read -p 'This is an irreversible action, please type "Yes" to proceed: ' acceptance

if [ "$acceptance" = "Yes" ] || [ "$acceptance" = "Y" ]
then
    #Promote the read replica in the DR region
    echo "Promoting the replica to a standalone instance..."
    gcloud sql instances promote-replica $drInstance
    echo "Instance promoted."

    #Set maintenance windows identical to last master
    echo "The instance will be upgraded and restarted"
    gcloud sql instances patch $drInstance --maintenance-window-day=$maintenanceWindowDay --maintenance-window-hour=$maintenanceWindowHour

    #Pass back new connection info (name and IP)
    echo "Your new connection string for your Primary Instance is $drConnectionString and your new IP Address is $drIP."
    echo "Please update your Applications that need write access now to recover."
    echo "Be sure to check your monitoring dashboard at https://console.cloud.google.com/monitoring/dashboards/resourceList/cloudsql_database?_ga=2.191125034.1850381721.1584972854-846869614.1583449071"

    #Recreate replica the in primary instance location using primary name 
    echo "Replacing your legacy primary instance - creating an HA replica in $primaryRegion"
    gcloud beta sql instances create $primaryFailoverReplica --master-instance-name=$drNameNoQuotes --availability-type=REGIONAL --network=$primaryNetwork --assign-ip --region=$pRegion
    echo $(gcloud sql instances describe $primaryFailoverReplica --format="json") > tempFiles/primaryReplacementReplica.json
    primaryReplacementConnectionString=$(jq '.connectionName' tempFiles/primaryReplacementReplica.json)
    primaryReplacementIP=$(jq '.ipAddresses' tempFiles/primaryReplacementReplica.json)
    echo "Your new connection string for your replica is $primaryReplacementConnectionString and your new IP Address is $primaryReplacementIP"

    #Display summary (you migrated from x region to y region and created x replicas. Here are you connection strings...)
    echo "Failover is complete. You successfully migrated from $primaryInstace in $primaryZone to $drInstance in $drZone. Your cascading replicas are still functional and do not reqire any changes."

else
    echo "You did not confirm with a Yes. No changes have been made."
fi