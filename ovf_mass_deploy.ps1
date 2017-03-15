#Script: DeployOVF.ps1
#Author: Kyle Vidmar
#Contact: kyle.vidmar@gmail.com
#
#Description:
#Deploy up to 1000 OVFs and specify parameters with OVFTool

$null = Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
$null = Set-PowerCLIConfiguration -InvalidCertificateAction "Ignore" -Confirm:$false

$amount = $args[0] #How many to deploy
$OVF_PATH = $args[1] #Path to OVF file via HTTP or SMB
$username = $args[2] #Username of who is deploying (will be placed in annotation)
$Next_ID = $args[3] #Number to start deployment from, I.E if I was to deploy $amount=100 starting from $Next_ID=67 and it would deploy #s 67 to 167

<####################################
 # Constants
 ####################################>

$OVFTOOLPATH = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
$IP_PREFIX = "10.12." #Since we max at 1000 IPs the first 2 octets are always the same
$NETMASK = "255.255.224.0" 
$GATEWAY = "10.12.64.1"
$DNS_1 = "10.12.64.1"
$DNS_2 = "10.12.64.1"
$SEARCH_DOMAINS = "search.com"
$Management_Network = "MANAGEMENT"
$Datastore_Cluster = "GCP-Pods" #Will auto sort and pick datastore
$dvSwitch = "dvSwitch_To_Use"
$SN_Name_Prefix = "OVF-" #Will deploy using this prefix so OVF-001, OVF-002, etc etc
$ErrorActionPreference = "SilentlyContinue"
$DEF_USAGE_RESP = "Useage C:\DeployOVF.ps1 AMOUNT OVF_PATH USERNAME NEXT_ID"
$vCenterIP = "vCenter.ip.address.or.dns"
$Host_Cluster = "Cluster_In_VMWare_To_Deploy"
$Username = "DOMAIN\User"
$Password = "Password"
$batchpath = "c:\batchovf\exec" #This script runs the OVF deployments in parallel using batch files, and exec##.bat for the deployments.  Make sure c:\batchovf\ is created for this to work out of the box

<####################################
 # Main
 ####################################>

    Connect-VIServer -Server $vCenterIP -User $Username -Password $Password #Establish a connection to VMWare via PowerCLI
    
    for ($i=1; $i -le $amount; $i++){

    if ($Next_ID -eq "" -or $Next_ID -eq $null){$Next_ID = 1}
    if ($Next_ID -lt 255){$IP_ADDRESS = $ip_prefix + "70." + $Next_ID}
    if ($Next_ID -lt 509 -and $Next_ID -ge 255){
        $temp = ($Next_ID-254)
        $IP_ADDRESS = $ip_prefix + "71." + $temp}
    if ($Next_ID -lt 763 -and $Next_ID -ge 509){
        $temp = ($Next_ID-508)
        $IP_ADDRESS = $ip_prefix + "72." + $temp}
    if ($Next_ID -ge 763 -and $Next_ID -lt 1001){
        $temp = ($Next_ID-762)
        $IP_ADDRESS = $ip_prefix + "73." + $temp}
    if ($Next_ID -gt 1000){
        Write-Host "Error: Over 1000 sensors detected."
        exit
        }

    $Datastore = Get-Datastore -Location $Datastore_Cluster | Sort "FreeSpaceGB" -Descending | Select-Object -First 1 | Foreach{$_.name}
    $Network_A = "vSensor-$Next_ID-A"
    $Network_B = "vSensor-$Next_ID-B"
    $VMwareHost = Get-VMHost -Location $Host_Cluster | Sort "CpuUsageMhz" | Select -First 1 | Foreach{$_.name}
    $SN_Name = $SN_Name_Prefix + $Next_ID
    
    Write-Host "Deploying $SN_Name with $IP_ADDRESS"    
    $batchfile = $batchpath + $Next_ID + ".bat"

    $Command = '"' + $OVFTOOLPATH + '" --annotation="' + $username + '" --noSSLVerify --powerOn --allowExtraConfig --lax --disableVerification --skipManifestGeneration --acceptAllEulas --datastore="' + $Datastore+ '" --net:Management0-0="' + $Management_Network + '" --net:GigabitEthernet0-0="' + $Network_A + '" --net:GigabitEthernet0-1="' + $Network_B + '" --net:GigabitEthernet0-2="HOLDING" --name="' + $SN_Name + '" --diskMode=thin --prop:"fqdn"="' + $SN_Name + '" --prop:"dns1"="' + $DNS_1 + '" --prop:"dns2"="' + $DNS_2 + '" --prop:"searchdomains"="' + $SEARCH_DOMAINS + '" --prop:"ipv4.how"="Manual" --prop:"ipv4.addr"="' + $IP_ADDRESS + '" --prop:"ipv4.mask"="' + $NETMASK + '" --prop:"ipv4.gw"="' + $GATEWAY + '" --skipManifestCheck ' + $OVF_PATH + ' "vi://quali.gen@cisco.com:Password3@ful-vc06.cisco.com/FUB-GCP-PODS/host/' + $Host_Cluster + '/' + $VMwareHost + '"'
    Set-Content -Value $Command -Path $batchfile
    $sb = [scriptblock]::Create("$batchfile")
    Start-Sleep -s 5
    if ( -not ($Next_ID % 10) ) { 
    Write-Host "This is a multiple of 10, waiting for job to complete before continuing"
    Start-Job -ScriptBlock $sb | Wait-Job
    Write-Host "Successfully Started Deployment of $SN_Name"
    $removepath = $batchpath + "*"
    Remove-Item $removepath -Confirm:$false
    }
    if ($Next_ID % 10){
    Start-Job -ScriptBlock $sb
    Write-Host "Successfully Started Deployment of $SN_Name"
    }
    $Next_ID = $Next_ID + 1
    }


    Write-Host "Verifying all VMs are powered on..."
    Start-Sleep -s 20
    $VMs = get-vm | where-object{$_.name -like $SN_Name_Prefix + "*"}
    foreach($VM in $VMs){
        if($VM.PowerState -eq "PoweredOff"){$null = Start-VM $VM.name -Confirm:$false -ErrorAction SilentlyContinue}


    }
<####################################
 ####################################>
