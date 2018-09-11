require 'securerandom'

module Packer
  module Config
    class Provisioners

      def self.powershell_provisioner(command)
        {
          'type' => 'powershell',
          'inline' => [
            '$ErrorActionPreference = "Stop";',
            'trap { $host.SetShouldExit(1) }',
            command
          ]
        }
      end

      BOSH_PSMODULES = [
        {
          'type' => 'file',
          'source' => 'build/bosh-psmodules.zip',
          'destination' => 'C:\\provision\\bosh-psmodules.zip'
        }, {
          'type' => 'powershell',
          'scripts' => ['scripts/install-bosh-psmodules.ps1']
        }
      ].freeze
      NEW_PROVISIONER = powershell_provisioner('New-Provisioner')
      INSTALL_KB4056898 = {
        'type' => 'windows-restart',
        'restart_command' => "powershell.exe -Command Install-KB4056898",
        'restart_timeout' => '1h'
      }
      INSTALL_KB2538243 = {
          'type' => 'windows-restart',
          'restart_command' => "powershell.exe -Command Install-KB2538243",
          'restart_timeout' => '1h'
      }
      INSTALL_CF_FEATURES_2016  = {
        'type' => 'windows-restart',
        'restart_command' => "powershell.exe -Command Install-CFFeatures",
        'restart_timeout' => '1h'
      }
      INSTALL_CF_FEATURES_1803_AZURE = {
          'type' => 'windows-restart',
          'restart_command' => "powershell.exe -Command Install-CFFeatures",
          'restart_timeout' => '1h',
          'restart_check_command'=> "powershell -command \"& {Write-Output 'restarted.'}\""
      }
      WAIT_AND_RESTART = {
        'type' => 'windows-restart',
        'restart_command' => 'powershell.exe -Command Start-Sleep -Seconds 900; Restart-Computer -Force',
        'restart_timeout' => '1h'
      }
      INSTALL_CF_FEATURES_2012 = powershell_provisioner('Install-CFFeatures')
      PROTECT_CF_CELL = powershell_provisioner('Protect-CFCell')
      OPTIMIZE_DISK = powershell_provisioner('Optimize-Disk')
      COMPRESS_DISK = powershell_provisioner('Compress-Disk')
      CLEAR_PROVISIONER = powershell_provisioner('Clear-Provisioner')
      GET_LOG = powershell_provisioner('Get-Log')
      CLEAR_PROXY_SETTINGS = powershell_provisioner('Clear-ProxySettings')
      ENABLE_CVE_2015_6161 = powershell_provisioner('Enable-CVE-2015-6161')
      ENABLE_CVE_2017_8529 = powershell_provisioner('Enable-CVE-2017-8529')
      Disable_RC4 = powershell_provisioner('Disable-RC4')
      Disable_TLS1 = powershell_provisioner('Disable-TLS1')
      Disable_3DES = powershell_provisioner('Disable-3DES')
      Disable_DCOM = powershell_provisioner('Disable-DCOM')
      ENABLE_CREDSSP = powershell_provisioner('Enable-CredSSP')

      def self.setup_proxy_settings(http_proxy, https_proxy, bypass_list)
        return powershell_provisioner("Set-ProxySettings #{http_proxy} #{https_proxy} #{bypass_list}")
      end

      def self.install_windows_updates
        password = SecureRandom.hex(10)+"!"
        return [
          powershell_provisioner("Add-Account -User Provisioner -Password #{password}"),
          powershell_provisioner("Register-WindowsUpdatesTask"),
          {
            'type' => 'windows-restart',
            'restart_command' => "powershell.exe -Command Wait-WindowsUpdates -Password #{password} -User Provisioner",
            'restart_timeout' => '12h'
          },
          powershell_provisioner("Unregister-WindowsUpdatesTask"),
          powershell_provisioner("Remove-Account -User Provisioner"),
          powershell_provisioner("Test-InstalledUpdates")
        ]
      end

      def self.download_windows_updates(dest)
        return [
          powershell_provisioner('Get-Hotfix | Out-File -FilePath "C:\\updates.txt" -Encoding ASCII'),
          {
            'type' => 'file',
            'source' => 'C:\\updates.txt',
            'destination' => File.join(dest, 'updates.txt'),
            'direction' => 'download'
          }
        ]
      end

      def self.install_agent(iaas, mount_ephemeral_disk = false)
        command = "Install-Agent -IaaS #{iaas} -agentZipPath 'C:\\provision\\agent.zip'"
        if mount_ephemeral_disk
          command << " -EnableEphemeralDiskMounting"
        end
        return [
          {
            'type' => 'file',
            'source' => 'build/agent.zip',
            'destination' => 'C:\\provision\\agent.zip'
          },
          powershell_provisioner(command)
        ]
      end

      def self.remove_docker(os)
        if os == 'windows1803'
          return {
            'type' => 'windows-restart',
            'restart_command' => "powershell.exe -Command Remove-DockerPackage",
            "restart_check_command" => "powershell -command \"& {Write-Output 'restarted.'}\""
          }
        end
        [] # Deal with non-returning case
      end

      INSTALL_SSHD = [
        {
          'type' => 'file',
          'source' => '../sshd/OpenSSH-Win64.zip',
          'destination' => 'C:\\provision\\OpenSSH-Win64.zip'
        },
        powershell_provisioner("Install-SSHD -SSHZipFile 'C:\\provision\\OpenSSH-Win64.zip'")
      ]

      def self.lgpo_exe
        {
          'type' => 'file',
          'source' => File.join(Stemcell::Builder::validate_env_dir('STEMCELL_DEPS_DIR'), 'lgpo', 'LGPO.exe'),
          'destination' => 'C:\\windows\\LGPO.exe'
        }.freeze
      end

      def self.sysprep_shutdown(iaas)
        return [powershell_provisioner("Invoke-Sysprep -IaaS #{iaas}")]
      end
    end
  end
end
