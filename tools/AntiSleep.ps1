clear host

write-host "Leaving this window open prevents your PC going to sleep whilst your mod is running"
write-host "This window will automatically close once your mod has finished and will restore your original power plan settings"
write-host "Alternatively you can close this window at any time"

$host.ui.RawUI.WindowTitle = 'AntiSleep'

Do {
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
[System.Windows.Forms.SendKeys]::SendWait("+{F15}")

Start-Sleep -Seconds 120

} While ($true)