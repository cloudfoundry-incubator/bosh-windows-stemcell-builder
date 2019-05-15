require 'packer/config'
require 'timecop'

describe Packer::Config::Aws do
  describe 'builders' do
    before :each do
      Timecop.freeze
    end

    after :each do
      Timecop.return
    end

    let(:region) do
      {
        name: 'region1',
        base_ami: 'baseami1',
        vpc_id: 'vpc1',
        subnet_id: 'subnet1',
        security_group: 'sg1'
      }
    end

    let(:builders) do
      Packer::Config::Aws.new(
        aws_access_key: 'some-aws-access-key',
        aws_secret_key: 'some-aws-secret-key',
        region: region,
        output_directory: 'some-output-directory',
        os: os,
        version: '',
        vm_prefix: 'some-vm-prefix'
      ).builders
    end

    let(:baseline_builders) do
      {
        name: 'amazon-ebs-region1',
        type: 'amazon-ebs',
        access_key: 'some-aws-access-key',
        secret_key: 'some-aws-secret-key',
        region: 'region1',
        source_ami: 'baseami1',
        instance_type: 'm4.large',
        vpc_id: 'vpc1',
        subnet_id: 'subnet1',
        associate_public_ip_address: true,
        launch_block_device_mappings: [
          {
            'device_name': '/dev/sda1',
            'volume_size': 30,
            'volume_type': 'gp2',
            'delete_on_termination': true,
          }
        ],
        communicator: 'winrm',
        winrm_username: 'Administrator',
        winrm_timeout: '1h',
        security_group_id: 'sg1',
        ami_groups: 'all',
        run_tags: { Name: "some-vm-prefix-#{Time.now.to_i}" }
      }
    end

    context 'all OSs' do
      let(:os) { '' }

      it 'returns the baseline builders' do
        expect(builders[0]).to include(baseline_builders)
        expect(builders[0][:ami_name]).to match(/BOSH-.*-region1/)
        expect(builders[0][:user_data_file]).to match(/.*scripts\/aws\/setup_winrm.txt$/)
      end
    end

    context 'windows2012R2' do
      let(:os) { 'windows2012R2' }

      it 'returns the expected builders with a 128GB root disk' do
        expect(builders[0]).to include(baseline_builders.merge({
                                                                   instance_type: 'm4.xlarge',
                                                                   launch_block_device_mappings: [
                                                                       {
                                                                           device_name: '/dev/sda1',
                                                                           volume_size: 128,
                                                                           volume_type: 'gp2',
                                                                           delete_on_termination: true,
                                                                       }
                                                                   ],
                                                               }))
      end
    end

    context 'when vm_prefix is empty' do
      it 'defaults to packer' do
        builders = Packer::Config::Aws.new(
          aws_access_key: '',
          aws_secret_key: '',
          region: region,
          output_directory: '',
          os: '',
          version: '',
          vm_prefix: ''
        ).builders
        expect(builders[0]).to include(
          run_tags: { Name: "packer-#{Time.now.to_i}" }
        )
      end
    end
  end

  describe 'provisioners' do
    before(:each) do
      @stemcell_deps_dir = Dir.mktmpdir('gcp')
      ENV['STEMCELL_DEPS_DIR'] = @stemcell_deps_dir
    end

    after(:each) do
      FileUtils.rm_rf(@stemcell_deps_dir)
      ENV.delete('STEMCELL_DEPS_DIR')
    end

    context 'windows 2012' do
      it 'returns the expected provisioners' do
        allow(SecureRandom).to receive(:hex).and_return("some-password")
        provisioners = Packer::Config::Aws.new(
          aws_access_key: '',
          aws_secret_key: '',
          region: '',
          output_directory: 'some-output-directory',
          os: 'windows2012R2',
          version: '2012R2.12',
          vm_prefix: '',
          mount_ephemeral_disk: false
        ).provisioners
        expected_provisioners_except_lgpo = [
          {"type"=>"file", "source"=>"build/bosh-psmodules.zip", "destination"=>"C:\\provision\\bosh-psmodules.zip", "pause_before"=>"60s"},
          {"type"=>"file", "source"=>"scripts/install-bosh-psmodules.ps1", "destination"=>"C:\\provision\\install-bosh-psmodules.ps1", "pause_before"=>"60s"},
          {"type"=>"powershell", "inline"=>['$ErrorActionPreference = "Stop";', 'C:\\provision\\install-bosh-psmodules.ps1'], 'pause_before'=>'60s'},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Add-Account -User Provisioner -Password some-password!"]},
          {'type'=>'powershell', 'inline'=>['$ErrorActionPreference = "Stop";',
                                            'trap { $host.SetShouldExit(1) }',
                                            'Upgrade-PSVersion'],
                                'elevated_user' => 'Provisioner',
                                'elevated_password' => "some-password!",
                                'pause_before'=>'30s'
          },
          {"type" => "windows-restart" },
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "New-Provisioner"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-CFFeatures"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Register-WindowsUpdatesTask"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Wait-WindowsUpdates -Password some-password! -User Provisioner"]},
          {"type"=>"windows-restart", "restart_timeout"=>"12h"},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Unregister-WindowsUpdatesTask"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-Account -User Provisioner"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Test-InstalledUpdates"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Protect-CFCell"]},
          {"type"=>"file", "source"=>"../sshd/OpenSSH-Win64.zip", "destination"=>"C:\\provision\\OpenSSH-Win64.zip"},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-SSHD -SSHZipFile 'C:\\provision\\OpenSSH-Win64.zip'"]},
          {"type"=>"file", "source"=>"build/agent.zip", "destination"=>"C:\\provision\\agent.zip"},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-Agent -IaaS aws -agentZipPath 'C:\\provision\\agent.zip'"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }",
                                                "New-Item 'C:\\var\\vcap\\bosh\\etc' -ItemType 'directory'",
                                                "New-Item -Path 'C:\\var\\vcap\\bosh\\etc\\stemcell_version' -ItemType 'file' -Value '2012R2.12'"] },
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-CVE-2015-6161"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-CVE-2017-8529"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-CredSSP"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-RC4"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS1"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS11"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-TLS12"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-3DES"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-DCOM"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-SSHKeys"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Clear-Provisioner"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Invoke-Sysprep -IaaS aws"]}
        ].flatten
        expect(provisioners.detect {|x| x['destination'] == "C:\\windows\\LGPO.exe"}).not_to be_nil
        provisioners_no_lgpo = provisioners.delete_if {|x| x['destination'] == "C:\\windows\\LGPO.exe"}
        expect(provisioners_no_lgpo).to eq (expected_provisioners_except_lgpo)
      end
    end

    context 'windows 2016' do
      it 'returns the expected provisioners' do
        stemcell_deps_dir = Dir.mktmpdir('aws')
        ENV['STEMCELL_DEPS_DIR'] = stemcell_deps_dir

        allow(SecureRandom).to receive(:hex).and_return("some-password")
        provisioners = Packer::Config::Aws.new(
          aws_access_key: '',
          aws_secret_key: '',
          region: '',
          output_directory: 'some-output-directory',
          os: 'windows2016',
          version: '2016.76',
          vm_prefix: '',
        ).provisioners
        expected_provisioners_except_lgpo = [
          {"type"=>"file", "source"=>"build/bosh-psmodules.zip", "destination"=>"C:\\provision\\bosh-psmodules.zip", "pause_before"=>"60s"},
          {"type"=>"file", "source"=>"scripts/install-bosh-psmodules.ps1", "destination"=>"C:\\provision\\install-bosh-psmodules.ps1", "pause_before"=>"60s"},
          {"type"=>"powershell", "inline"=>['$ErrorActionPreference = "Stop";', 'C:\\provision\\install-bosh-psmodules.ps1'], "pause_before"=>"60s"},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "New-Provisioner"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-DockerPackage"]},
          {"type" => "windows-restart", "restart_timeout" => "1h" },
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-CFFeatures2016"]},
          {"type" => "windows-restart", "restart_timeout" => "1h" },
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Add-Account -User Provisioner -Password some-password!"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Register-WindowsUpdatesTask"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Wait-WindowsUpdates -Password some-password! -User Provisioner"]},
          {"type" => "windows-restart", "restart_timeout" => "12h"},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Unregister-WindowsUpdatesTask"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-Account -User Provisioner"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Protect-CFCell"]},
          {"type"=>"file", "source"=>"../sshd/OpenSSH-Win64.zip", "destination"=>"C:\\provision\\OpenSSH-Win64.zip"},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-SSHD -SSHZipFile 'C:\\provision\\OpenSSH-Win64.zip'"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-SSHD"]},
          {"type"=>"file", "source"=>"build/agent.zip", "destination"=>"C:\\provision\\agent.zip"},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-Agent -IaaS aws -agentZipPath 'C:\\provision\\agent.zip'"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }",
                                                "New-Item 'C:\\var\\vcap\\bosh\\etc' -ItemType 'directory'",
                                                "New-Item -Path 'C:\\var\\vcap\\bosh\\etc\\stemcell_version' -ItemType 'file' -Value '2016.76'"] },
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-RC4"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS1"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS11"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-TLS12"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-3DES"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Get-WUCerts"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-SSHKeys"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Clear-Provisioner"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Invoke-Sysprep -IaaS aws"]}
        ].flatten
        expect(provisioners.detect {|x| x['destination'] == "C:\\windows\\LGPO.exe"}).not_to be_nil
        provisioners_no_lgpo = provisioners.delete_if {|x| x['destination'] == "C:\\windows\\LGPO.exe"}
        expect(provisioners_no_lgpo).to eq (expected_provisioners_except_lgpo)

        FileUtils.rm_rf(stemcell_deps_dir)
        ENV.delete('STEMCELL_DEPS_DIR')
      end

      context 'when provisioning with emphemeral disk mounting enabled' do
        it 'calls Install-Agent with -EnableEphemeralDiskMounting' do
          allow(SecureRandom).to receive(:hex).and_return("some-password")
          provisioners = Packer::Config::Aws.new(
            aws_access_key: '',
            aws_secret_key: '',
            region: '',
            output_directory: 'some-output-directory',
            os: 'windows2016',
            version: '',
            vm_prefix: '',
            mount_ephemeral_disk: true,
          ).provisioners

          expect(provisioners).to include(
            {
              "type"=>"powershell",
              "inline"=>[
                "$ErrorActionPreference = \"Stop\";",
                "trap { $host.SetShouldExit(1) }",
                "Install-Agent -IaaS aws -agentZipPath 'C:\\provision\\agent.zip' -EnableEphemeralDiskMounting"
              ]
            }
          )
        end
      end
    end

    context 'windows 1803' do
      it 'returns the expected provisioners' do
        stemcell_deps_dir = Dir.mktmpdir('aws')
        ENV['STEMCELL_DEPS_DIR'] = stemcell_deps_dir

        allow(SecureRandom).to receive(:hex).and_return("some-password")
        provisioners = Packer::Config::Aws.new(
          aws_access_key: '',
          aws_secret_key: '',
          region: '',
          version: '1803.24',
          output_directory: 'some-output-directory',
          os: 'windows1803',
          vm_prefix: '',
        ).provisioners
        expected_provisioners_base = [
          {"type" => "file", "source" => "build/bosh-psmodules.zip", "destination" => "C:\\provision\\bosh-psmodules.zip", "pause_before"=>"60s"},
          {"type"=>"file", "source"=>"scripts/install-bosh-psmodules.ps1", "destination"=>"C:\\provision\\install-bosh-psmodules.ps1", "pause_before"=>"60s"},
          {"type"=>"powershell", "inline"=>['$ErrorActionPreference = "Stop";', 'C:\\provision\\install-bosh-psmodules.ps1'], "pause_before"=>"60s"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "New-Provisioner"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-DockerPackage"]},
          {"type" => "windows-restart", "restart_timeout" => "1h" },
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-CFFeatures2016"]},
          {"type" => "windows-restart", "restart_timeout" => "1h"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Add-Account -User Provisioner -Password some-password!"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Register-WindowsUpdatesTask"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Wait-WindowsUpdates -Password some-password! -User Provisioner"]},
          {"type" => "windows-restart", "restart_timeout" => "12h"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Unregister-WindowsUpdatesTask"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-Account -User Provisioner"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Protect-CFCell"]},
          {"type" => "file", "source" => "../sshd/OpenSSH-Win64.zip", "destination" => "C:\\provision\\OpenSSH-Win64.zip"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-SSHD -SSHZipFile 'C:\\provision\\OpenSSH-Win64.zip'"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-SSHD"]},
          {"type" => "file", "source" => "build/agent.zip", "destination" => "C:\\provision\\agent.zip"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-Agent -IaaS aws -agentZipPath 'C:\\provision\\agent.zip'"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-RC4"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS1"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS11"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-TLS12"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-3DES"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Get-WUCerts"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-SSHKeys"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Clear-Provisioner"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Invoke-Sysprep -IaaS aws"]}
        ].flatten
        expect(provisioners.detect {|x| x['destination'] == "C:\\windows\\LGPO.exe"}).not_to be_nil
        expect(provisioners.detect do |p|
                  p.has_key?('inline')
                end).not_to be_nil
        expect(provisioners.detect do |p|
          p.has_key?('inline') && p['inline'].include?("New-VersionFile -Version")
        end).not_to be_nil, "Expect provisioners to include New-VersionFile"
        line_by_line_provisioners = provisioners.delete_if {|x| x['destination'] == "C:\\windows\\LGPO.exe"}
        line_by_line_provisioners = line_by_line_provisioners.delete_if {|x| x .has_key?('inline') && x['inline'].include?("New-VersionFile -Version")}
        expect(line_by_line_provisioners).to eq (expected_provisioners_base)

        FileUtils.rm_rf(stemcell_deps_dir)
        ENV.delete('STEMCELL_DEPS_DIR')
      end

      context 'when provisioning with emphemeral disk mounting enabled' do
        it 'calls Install-Agent with -EnableEphemeralDiskMounting' do
          allow(SecureRandom).to receive(:hex).and_return("some-password")
          provisioners = Packer::Config::Aws.new(
            aws_access_key: '',
            aws_secret_key: '',
            region: '',
            output_directory: 'some-output-directory',
            os: 'windows1803',
            version: '',
            vm_prefix: '',
            mount_ephemeral_disk: true,
          ).provisioners

          expect(provisioners).to include(
            {
              "type" => "powershell",
              "inline" => [
                "$ErrorActionPreference = \"Stop\";",
                "trap { $host.SetShouldExit(1) }",
                "Install-Agent -IaaS aws -agentZipPath 'C:\\provision\\agent.zip' -EnableEphemeralDiskMounting"
              ]
            }
          )
        end
      end
    end

    context 'windows 2019' do
      it 'returns the expected provisioners' do
        stemcell_deps_dir = Dir.mktmpdir('aws')
        ENV['STEMCELL_DEPS_DIR'] = stemcell_deps_dir

        allow(SecureRandom).to receive(:hex).and_return("some-password")
        provisioners = Packer::Config::Aws.new(
          aws_access_key: '',
          aws_secret_key: '',
          region: '',
          output_directory: 'some-output-directory',
          os: 'windows2019',
          version: '2019.43',
          vm_prefix: '',
          ).provisioners
        expected_provisioners_except_lgpo = [
          {"type" => "file", "source" => "build/bosh-psmodules.zip", "destination" => "C:\\provision\\bosh-psmodules.zip", "pause_before"=>"60s"},
          {"type"=>"file", "source"=>"scripts/install-bosh-psmodules.ps1", "destination"=>"C:\\provision\\install-bosh-psmodules.ps1", "pause_before"=>"60s"},
          {"type"=>"powershell", "inline"=>['$ErrorActionPreference = "Stop";', 'C:\\provision\\install-bosh-psmodules.ps1'], "pause_before"=>"60s"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "New-Provisioner"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-DockerPackage"]},
          {"type" => "windows-restart", "restart_timeout" => "1h" },
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-CFFeatures2016"]},
          {"type" => "windows-restart", "restart_timeout" => "1h"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Add-Account -User Provisioner -Password some-password!"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Register-WindowsUpdatesTask"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Wait-WindowsUpdates -Password some-password! -User Provisioner"]},
          {"type" => "windows-restart", "restart_timeout" => "12h"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Unregister-WindowsUpdatesTask"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-Account -User Provisioner"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Protect-CFCell"]},
          {"type" => "file", "source" => "../sshd/OpenSSH-Win64.zip", "destination" => "C:\\provision\\OpenSSH-Win64.zip"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-SSHD -SSHZipFile 'C:\\provision\\OpenSSH-Win64.zip'"]},
          {"type"=>"powershell", "inline"=> ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-SSHD"]},
          {"type" => "file", "source" => "build/agent.zip", "destination" => "C:\\provision\\agent.zip"},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Install-Agent -IaaS aws -agentZipPath 'C:\\provision\\agent.zip'"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }",
                                                "New-Item 'C:\\var\\vcap\\bosh\\etc' -ItemType 'directory'",
                                                "New-Item -Path 'C:\\var\\vcap\\bosh\\etc\\stemcell_version' -ItemType 'file' -Value '2019.43'"] },
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-RC4"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS1"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-TLS11"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Enable-TLS12"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Disable-3DES"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Get-WUCerts"]},
          {"type"=>"powershell", "inline"=>["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Remove-SSHKeys"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Clear-Provisioner"]},
          {"type" => "powershell", "inline" => ["$ErrorActionPreference = \"Stop\";", "trap { $host.SetShouldExit(1) }", "Invoke-Sysprep -IaaS aws"]}
        ].flatten
        expect(provisioners.detect {|x| x['destination'] == "C:\\windows\\LGPO.exe"}).not_to be_nil
        provisioners_no_lgpo = provisioners.delete_if {|x| x['destination'] == "C:\\windows\\LGPO.exe"}
        expect(provisioners_no_lgpo).to eq (expected_provisioners_except_lgpo)

        FileUtils.rm_rf(stemcell_deps_dir)
        ENV.delete('STEMCELL_DEPS_DIR')
      end

      context 'when provisioning with emphemeral disk mounting enabled' do
        it 'calls Install-Agent with -EnableEphemeralDiskMounting' do
          allow(SecureRandom).to receive(:hex).and_return("some-password")
          provisioners = Packer::Config::Aws.new(
            aws_access_key: '',
            aws_secret_key: '',
            region: '',
            output_directory: 'some-output-directory',
            os: 'windows2019',
            version: '',
            vm_prefix: '',
            mount_ephemeral_disk: true,
            ).provisioners

          expect(provisioners).to include(
                                    {
                                      "type" => "powershell",
                                      "inline" => [
                                        "$ErrorActionPreference = \"Stop\";",
                                        "trap { $host.SetShouldExit(1) }",
                                        "Install-Agent -IaaS aws -agentZipPath 'C:\\provision\\agent.zip' -EnableEphemeralDiskMounting"
                                      ]
                                    }
                                  )
        end
      end
    end

  end
end
