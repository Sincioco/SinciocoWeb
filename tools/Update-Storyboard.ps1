[CmdletBinding(DefaultParameterSetName='Update')]
param(
 [Parameter(ParameterSetName='DryRun')][switch]$DryRun,
 [Parameter(ParameterSetName='Check')][switch]$Check,
 [Parameter(ParameterSetName='Restore',Mandatory=$true)][string]$Restore
)
$ErrorActionPreference='Stop'
$arguments=@((Join-Path $PSScriptRoot 'update_storyboard.py'))
if($DryRun){$arguments+='--dry-run'}
if($Check){$arguments+='--check'}
if($Restore){$arguments+=@('--restore',$Restore)}
& python @arguments
if($LASTEXITCODE -ne 0){throw 'Storyboard publication update/validation failed.'}
