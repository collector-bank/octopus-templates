#$ResourceGroup = "test"
#$WebAppName = "test"
#$SlotName = "test"
#$Domain = "test"

function WaitForExistanceOfSlot
{
    Write-Host "WaitForExistanceOfSlot"
    $retryCount = 0
    while(!(Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroup -Name $WebAppName -Slot $SlotName -ErrorAction SilentlyContinue ))
    {
        Write-Host "Failed to get staging slot. Retry count=$retryCount"
        Clear-DnsClientCache
        Sleep -Seconds 5
        $retryCount++
        if ($retryCount -eq 50) {
            exit 1
        }
    }
}

function WaitForRemovalOfSlot([int] $removeRetries)
{
    Write-Host "WaitForRemovalOfSlot $Domain, Retry count=$removeRetries"
    $retryCount = 0
    while(Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroup -Name $WebAppName -Slot $SlotName -ErrorAction SilentlyContinue )
    {
        Write-Host "Staging slot still not removed. Retry count=$retryCount"
        Sleep -Seconds 5
        $retryCount++
        if ($retryCount -eq 50) {
            return $false
        }
    }
    return $true
}

Write-Host "New-DeploymentSlot: ResourceGroup=$ResourceGroup, WebAppName = $WebAppName, SlotName=staging"

[int] $removeRetries=0
do
{
    # Suggest to azure that the staging slot might be removed
    $oldSlot = Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroup -Name $WebAppName -Slot $SlotName -ErrorAction SilentlyContinue
    Remove-AzureRMWebAppSlot -Name $WebAppName -Slot $SlotName -ResourceGroupName $ResourceGroup -Force -ErrorAction SilentlyContinue
}
while (!(WaitForRemovalOfSlot ($removeRetries++)) -and $removeRetries -lt 10)

# Create the api staging slot
$newSlot = New-AzureRMWebAppSlot -Name $WebAppName -Slot $SlotName -ResourceGroupName $ResourceGroup -ErrorAction Stop

# Wait for slot to come into existance
WaitForExistanceOfSlot

# Stop web jobs in staging slot
$webAppSlot = Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroup -Name $WebAppName -Slot $SlotName
$appSettingsClone = @{}
foreach ($kvp in $webAppSlot.SiteConfig.AppSettings)
{
    $appSettingsClone[$kvp.Name] = $kvp.Value
}
$appSettingsClone['WEBJOBS_STOPPED'] = "1"

Set-AzureRmWebAppSlot -Name $WebAppName -Slot $SlotName -ResourceGroupName $ResourceGroup -AppSettings $appSettingsClone | Out-Null
#Write-Host "Web job appsettings applied: `n $($appSettingsClone | ConvertTo-Json)"

$stickySlotConfigObject = @{
    "connectionStringNames" = @()
    "appSettingNames" = @("WEBJOBS_STOPPED")
}

## Sets the "WEBJOBS_STOPPED" setting as a sticky setting on all the slots
Set-AzureRmResource -PropertyObject $stickySlotConfigObject -ResourceGroupName $ResourceGroup -ResourceType Microsoft.Web/sites/config -ResourceName $WebAppName/slotConfigNames -ApiVersion 2015-08-01 -Force | Out-Null

# Log finish
Write-Host "New-DeploymentSlot done."
