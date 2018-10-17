require 'fileutils'
require 'json'
require 'rake'
require 'rubygems/package'
require 'tmpdir'
require 'yaml'
require 'zlib'

load File.expand_path('../../../../lib/tasks/package/bwats.rake', __FILE__)

describe 'Package::BWATS' do
	before(:each) do
		@original_env = ENV.to_hash
		@build_dir = File.expand_path('../../../../build', __FILE__)
		FileUtils.mkdir_p(@build_dir)
		Rake::Task['package:bwats'].reenable
	end

	after(:each) do
		ENV.replace(@original_env)
		FileUtils.rm_rf(@build_dir)
	end

	it 'should catch missing env variables' do
		ENV['AZ'] = nil
		task = Rake::Task['package:bwats']
		expect {task.clone.invoke}.to raise_exception("missing environment variables")
	end

	it 'should package bosh-windows-acceptance-tests (BWATS) config.json' do
		config = {
			'bosh' => {
				'ca_cert' => 'some-cert',
				'client' => 'some-client',
				'client_secret' => 'some-secret',
				'target' => 'some-target'
			},
			'stemcell_path' => File.absolute_path('some-path'),
			'stemcell_os' => 'some-os',
			'az' => 'some-az',
			'vm_type' => 'some-type',
			'root_ephemeral_vm_type' => 'some-root-ephemeral-type',
			'vm_extensions' => 'some-vm-extensions',
			'mount_ephemeral_disk' => false,
			'network' => 'some-network',
      'skip_ms_update_test' => false
		}
		ENV['BOSH_CA_CERT'] = config['bosh']['ca_cert']
		ENV['BOSH_CLIENT']= config['bosh']['client']
		ENV['BOSH_CLIENT_SECRET'] = config['bosh']['client_secret']
		ENV['BOSH_TARGET']= config['bosh']['target']
		ENV['STEMCELL_PATH']= config['stemcell_path']
		ENV['STEMCELL_OS']= config['stemcell_os']
		ENV['AZ']= config['az']
		ENV['VM_TYPE']= config['vm_type']
		ENV['ROOT_EPHEMERAL_VM_TYPE']= config['root_ephemeral_vm_type']
		ENV['VM_EXTENSIONS']= config['vm_extensions']
		ENV['NETWORK']= config['network']
		Rake::Task['package:bwats'].invoke
		pattern = File.join(@build_dir, "config.json").gsub('\\', '/')
		files = Dir.glob(pattern)
		expect(files.length).to eq(1)
		content = File.open(files[0], 'rb') { |f| f.read }
		expect(JSON.parse(content)).to eq(config)
		pattern = File.join(@build_dir, "ginkgo*").gsub('\\', '/')
		files = Dir.glob(pattern)
		expect(files.length).to eq(1)
	end

end
