#!/bin/bash

#Set preject variables
gcloud auth login
read -p 'Please provide Project ID for the project that your instance is located in:' project
gcloud config set project $project

#Make a temp directory and file to store the JSON output from Gcloud
mkdir tempFiles
touch tempFiles/instanceDetails-currentPrimary.json
touch tempFiles/instanceDetails-failbackinstance.json
touch tempFiles/instanceDetails-legacyPrimary.json
touch tempFiles/replica1.json
touch tempFiles/replica2.json
touch tempFiles/replica3.json
touch tempFiles/replica4.json
touch tempFiles/replica5.json
touch tempFiles/failbackReplacementReplica.json

#Prompt the user for the primary instance and target failover replica
read -p 'Enter the Instance ID of your current primary instance: ' primaryInstance
read -p 'Enter the Instance ID of the HA replica you would like to failover to: ' failbackInstance
read -p 'Enter the Instance ID of the orignal primary instance: ' legacyInstance

#Pull all data from primary instance needed for scripting
echo "Pulling Data from your SQL instances..."
echo $(gcloud sql instances describe $primaryInstance --format="json") > tempFiles/instanceDetails-currentPrimary.json
echo $(gcloud sql instances describe $failbackInstance --format="json") > tempFiles/instanceDetails-failbackinstance.json
echo $(gcloud sql instances describe $legacyInstance --format="json") > tempFiles/instanceDetails-legacyPrimary.json

#Store Primary instance variables locally
primaryRegion=$(jq '.region' tempFiles/instanceDetails-currentPrimary.json)
pRegion=$(echo $primaryRegion | sed 's/^"\(.*\)"$/\1/')
primaryZone=$(jq '.gceZone' tempFiles/instanceDetails-currentPrimary.json)
pZone=$(echo $primaryZone | sed 's/^"\(.*\)"$/\1/')
primaryName=$(jq '.name' tempFiles/instanceDetails-currentPrimary.json)
primaryTier=$(jq '.settings.tier' tempFiles/instanceDetails-currentPrimary.json)
primaryDataDiskSizeGb=$(jq '.settings.dataDiskSizeGb' tempFiles/instanceDetails-currentPrimary.json)
primaryDataDiskType=$(jq '.settings.dataDiskType' tempFiles/instanceDetails-currentPrimary.json)
primaryNetwork=$(jq '.settings.ipConfiguration.privateNetwork' tempFiles/instanceDetails-currentPrimary.json)
primaryNetwork=$(echo ${primaryNetwork##*/})
primaryNetwork=$(echo ${primaryNetwork::-1})
maintenanceWindowDay=$(jq '.settings.maintenanceWindow.day' tempFiles/instanceDetails-currentPrimary.json)
maintenanceWindowHour=$(jq '.settings.maintenanceWindow.hour' tempFiles/instanceDetails-currentPrimary.json)
primaryIP=$(jq '.ipAddresses' tempFiles/instanceDetails-currentPrimary.json)
replica1=$(jq '.replicaNames[0]' tempFiles/instanceDetails-currentPrimary.json)
replica2=$(jq '.replicaNames[1]' tempFiles/instanceDetails-currentPrimary.json)
replica3=$(jq '.replicaNames[2]' tempFiles/instanceDetails-currentPrimary.json)
replica4=$(jq '.replicaNames[3]' tempFiles/instanceDetails-currentPrimary.json)
replica5=$(jq '.replicaNames[4]' tempFiles/instanceDetails-currentPrimary.json)
backupHours=$(jq '.settings.backupConfiguration.startTime' tempFiles/instanceDetails-currentPrimary.json | cut -c2-3)
backupMinutes=$(jq '.settings.backupConfiguration.startTime' tempFiles/instanceDetails-currentPrimary.json | cut -c5-6)
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

#Store failback instance variables locally
failbackRegion=$(jq '.region' tempFiles/instanceDetails-failbackinstance.json)
failbackZone=$(jq '.zone' tempFiles/instanceDetails-failbackinstance.json)
failbackConnectionString=$(jq '.connectionName' tempFiles/instanceDetails-failbackinstance.json)
failbackIP=$(jq '.ipAddresses' tempFiles/instanceDetails-failbackinstance.json)
failbackName=$(jq '.name' tempFiles/instanceDetails-failbackinstance.json)
failbackNameNoQuotes=$(echo $failbackName| sed 's/^"\(.*\)"$/\1/')
primaryNameNoQuotes=$(echo $primaryName | sed 's/^"\(.*\)"$/\1/')
primaryFailoverReplica=$primaryNameNoQuotes-$randomid

#Store legacy primary instance variables locally (may not need this)
lpRegion=$(jq '.region' tempFiles/instanceDetails-dr.json)
lpZone=$(jq '.zone' tempFiles/instanceDetails-dr.json)
lpConnectionString=$(jq '.connectionName' tempFiles/instanceDetails-dr.json)
lpIP=$(jq '.ipAddresses' tempFiles/instanceDetails-dr.json)
lpName=$(jq '.name' tempFiles/instanceDetails-dr.json)
lpNameNoQuotes=$(echo $lpName| sed 's/^"\(.*\)"$/\1/')

echo "Data pull complete."

#create an array for the replicas to be stored in
replicas=()

#check each replica variable to see if it's null and if not, add it to array
echo "Checking for replicas..."

if [ "$replica1" != "null" ]
then
    replicas+=("$replica1")
    if [ "$replica2" != "null" ]
    then
        replicas+=("$replica2")
        if [ "$replica3" != "null" ]
        then
            replicas+=("$replica3")
            if [ "$replica4" != "null" ]
            then
                replicas+=("$replica4")
                if [ "$replica5" != "null" ]
                then
                    replicas+=("$replica5")
                fi
            fi
        fi
    fi
fi

#count the total number of replicas for deletion / reprovisioning purposes
totalReplicas="$(("${#replicas[*]}"-1))"


echo "We found $totalReplicas replicas in addition to the replica you specified as the target failover instance"

#ask user to confirm the action since it is irreversable
echo "You are attempting to failover from $primaryInstance in $primaryRegion to $failbackInstance in $failbackRegion. As part of this failover, your DR replica and read only replicas will be replaced as well."
read -p 'This is an irreversible action, please type Yes to proceed: ' acceptance

if [ "$acceptance" = "Yes" ] || [ "$acceptance" = "Y" ]
then
    #Promote the read replica in the failback region
    echo "Promoting the replica to a standalone instance..."
    gcloud sql instances promote-replica $failbackInstance
    echo "Instance promoted."

    #Set maintenance windows identical to last master
    echo "The instance will be upgraded and restarted"
    gcloud sql instances patch $failbackInstance --maintenance-window-day=$maintenanceWindowDay --maintenance-window-hour=$maintenanceWindowHour

    #Pass back new connection info (name and IP)
    echo "Your new connection string for your Primary Instance is $failbackConnectionString and your new IP Address is $failbackIP."
    echo "Please update your Applications that need write access now to recover."
    echo "Be sure to check your monitoring dashboard at https://console.cloud.google.com/monitoring/dashboards/resourceList/cloudsql_database?_ga=2.191125034.1850381721.1584972854-846869614.1583449071"

    #Recreate the HA DR replica in its current location using legacy HA replicas name 
    echo "Replacing your former primary instance with an HA replica - creating the replica in $primaryRegion"
    gcloud beta sql instances create $primaryFailoverReplica --master-instance-name=$failbackNameNoQuotes --availability-type=REGIONAL --network=$primaryNetwork --assign-ip --region=$pRegion
    echo $(gcloud sql instances describe $primaryFailoverReplica --format="json") > tempFiles/failbackReplacementReplica.json
    primaryReplacementConnectionString=$(jq '.connectionName' tempFiles/failbackReplacementReplica.json)
    primaryReplacementIP=$(jq '.ipAddresses' tempFiles/failbackReplacementReplica.json)
    echo "Your new connection string for your DR replica is $primaryReplacementConnectionString and your new IP Address is $primaryReplacementIP"

    #convert to zone, region combo array
    replicaLocations=()

    #Build replicaLocations Array and capture data
    if [ "$totalReplicas" != 0 ] 
    then 
        counter=1 
        for replica in "${replicas[@]}" 
        do 
            replica=$(echo $replica | sed 's/^"\(.*\)"$/\1/')
            if [ "$replica" != "$failbackInstance" ]
            then
                echo $(gcloud sql instances describe $replica --format="json") > tempFiles/replica$counter.json
                replicaZone=$(jq '.gceZone' tempFiles/replica$counter.json)
                replicaZone=$(echo $replicaZone | sed 's/^"\(.*\)"$/\1/')
                replicaRegion=$(jq '.region' tempFiles/replica$counter.json)
                replicaRegion=$(echo $replicaRegion | sed 's/^"\(.*\)"$/\1/')
                replicaLocations+=("$replicaZone, $replicaRegion")
                ((counter++))
            fi
        done
    fi


    #Recreate replicas 
        #Need to loop through old replicas before they are deleted and grab their region
        #Then reprovision them
        #Then pass back connectionName and IPs of each

    echo "Provisioning your cascading replicas."
    if [ "$totalReplicas" != 0 ]
    then
        counter=1
        for region in "${replicaLocations[@]}"
        do  
            #generate random string for naming
            randomid=$(echo $RANDOM | md5sum | head -c 5; echo;)

            #give the replica a name
            replicaName="$primaryFailoverReplica-Creplica-$randomid"

            echo "Creating a replica in $region"

            #Create the cascading replica mapped to new DR instance
            gcloud sql instances patch --backup-start-time=12:00 --project=$project $primaryFailoverReplica
            gcloud sql instances patch --enable-bin-log --project=$project $primaryFailoverReplica
            gcloud sql instances create $replicaName --master-instance-name=$primaryFailoverReplica --project=$project --region=$region
                
            echo $(gcloud sql instances describe $replicaName --format="json") > tempFiles/$replicaName.json
            replicaConnectionString=$(jq '.connectionName' tempFiles/$replicaName.json)
            replicaIP=$(jq '.connectionName' tempFiles/$replicaName.json)
            echo "Your new connection string for your replica is $replicaConnectionString and your new IP Address is $replicaIP"
            ((counter++))
        done
    else
        echo "There are no old replicas to replace"
    fi

    #Display summary
    echo "Failover is complete. You successfully migrated from $primaryInstace in $primaryZone to $failbackInstance in $failbackZone, and recreated replicas in the following locations:"
    for region in "${replicaZones[@]}"
    do
        echo $region
    done

    #provide code for deleting the legacy cascading replica

    #provide code for deleting the legacy HA DR replica
    
    #provide code for deleting the legacy primary instance

else
    echo "You did not confirm with a Yes. No changes have been made."
fi