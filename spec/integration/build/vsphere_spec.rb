require 'fileutils'
require 'json'
require 'rake'
require 'rubygems/package'
require 'tmpdir'
require 'yaml'
require 'zlib'

load File.expand_path('../../../../lib/tasks/build/vsphere.rake', __FILE__)

describe 'VSphere' do
  before(:each) do
    @original_env = ENV.to_hash
    @build_dir = File.expand_path('../../../../build', __FILE__)
    @output_directory = 'bosh-windows-stemcell'
    @version_dir = Dir.mktmpdir('vsphere')
    @vmx_version_dir = Dir.mktmpdir('vsphere')
    @stemcell_deps_dir = Dir.mktmpdir('vsphere')
    FileUtils.mkdir_p(@build_dir)
    FileUtils.rm_rf(@output_directory)

    Rake::Task['build:vsphere'].reenable
    Rake::Task['build:vsphere_add_updates'].reenable
    Rake::Task['build:vsphere_patchfile'].reenable
  end

  after(:each) do
    ENV.replace(@original_env)
    FileUtils.rm_rf(@build_dir)
    FileUtils.rm_rf(@output_directory)
    FileUtils.rm_rf(@version_dir)
    FileUtils.rm_rf(@vmx_version_dir)
    FileUtils.rm_rf(@stemcell_deps_dir)
  end

  describe 'add updates' do
    before(:each) do
      os_version = 'windows2012R2'

      ENV['AWS_ACCESS_KEY_ID']= 'some-key'
      ENV['AWS_SECRET_ACCESS_KEY'] = 'secret-key'
      ENV['AWS_REGION'] = 'some-region'
      ENV['INPUT_BUCKET'] = 'input-vmx-bucket'
      ENV['VMX_CACHE_DIR'] = '/tmp'
      ENV['OUTPUT_BUCKET'] = 'stemcell-output-bucket'
      ENV['VERSION_DIR'] = @version_dir

      ENV['ADMINISTRATOR_PASSWORD'] = 'pass'

      ENV['OS_VERSION'] = os_version
      ENV['PATH'] = "#{File.join(@build_dir, '..', 'spec', 'fixtures', 'vsphere')}:#{ENV['PATH']}"

      File.write(
        File.join(@version_dir, 'number'),
        'some-version'
      )

      s3_vmx= double(:s3_vmx)
      allow(s3_vmx).to receive(:fetch).and_return("1234")
      allow(s3_vmx).to receive(:put)

      allow(S3::Vmx).to receive(:new).with(
        input_bucket: 'input-vmx-bucket',
        output_bucket: 'stemcell-output-bucket',
        vmx_cache_dir: '/tmp',
        endpoint: nil)
        .and_return(s3_vmx)

      allow(S3).to receive(:test_upload_permissions)
    end

    it 'should build a vsphere_add_updates vmx' do
      Rake::Task['build:vsphere_add_updates'].invoke

      pattern = File.join(@output_directory, "*.vmx").gsub('\\', '/')
      files = Dir.glob(pattern)
      expect(files.length).to eq(1)
      expect(files[0]).to eq(File.join(@output_directory,"file.vmx"))
    end

    context 'when we are not authorized to upload to the S3 bucket' do
      before(:each) do
        allow(S3).to receive(:test_upload_permissions).and_raise(Aws::S3::Errors::Forbidden.new('', ''))
      end

      it 'should fail before building the vmx' do
        expect do
          Rake::Task['build:vsphere_add_updates'].invoke
        end.to raise_exception(Aws::S3::Errors::Forbidden)

        files = Dir.glob(File.join(@output_directory, '*').gsub('\\', '/'))
        expect(files).to be_empty
      end
    end
  end

  describe "with patchfile" do
    before(:each) do
      @os_version = 'windows2016'
      @version = '1200.3.1-build.2'
      agent_commit = 'some-agent-commit'

      ENV['AWS_ACCESS_KEY_ID']= 'some-key'
      ENV['AWS_SECRET_ACCESS_KEY'] = 'secret-key'
      ENV['AWS_REGION'] = 'some-region'
      ENV['AZURE_STORAGE_ACCOUNT_NAME'] = 'some-account-name'
      ENV['AZURE_STORAGE_ACCESS_KEY'] = 'some-access-key'
      ENV['AZURE_CONTAINER_NAME'] = 'container-name'
      ENV['CACHE_DIR'] = '/tmp'
      ENV['STEMCELL_OUTPUT_BUCKET'] = 'some-stemcell-output-bucket'
      ENV['OUTPUT_BUCKET'] = 'some-output-bucket'
      ENV['VHD_VMDK_BUCKET'] = 'some-vhd-vmdk-bucket'
      ENV['PATCH_OUTPUT_BUCKET'] = 'some-patch-output-bucket'

      ENV['ADMINISTRATOR_PASSWORD'] = 'pass'
      ENV['PRODUCT_KEY'] = 'product-key'
      ENV['OWNER'] = 'owner'
      ENV['ORGANIZATION'] = 'organization'

      ENV['OS_VERSION'] = @os_version
      ENV['VERSION_DIR'] = @version_dir
      ENV['STEMCELL_DEPS_DIR'] = @stemcell_deps_dir
      ENV['PATH'] = "#{File.join(@build_dir, '..', 'spec', 'fixtures', 'vsphere')}:#{ENV['PATH']}"

      ENV['OUTPUT_DIR'] = @output_directory

      FileUtils.mkdir_p(File.join(@build_dir, 'compiled-agent'))
      File.write(
        File.join(@build_dir, 'compiled-agent', 'sha'),
        agent_commit
      )

      File.write(
        File.join(@version_dir, 'number'),
        @version
      )
      File.write(
        File.join(@vmx_version_dir, 'number'),
        'some-vmx-version'
      )

      s3_vmx= double(:s3_vmx)
      allow(s3_vmx).to receive(:fetch).and_return("1234")
      allow(s3_vmx).to receive(:put)

      allow(S3::Vmx).to receive(:new).with(
        input_bucket: 'input-vmx-bucket',
        output_bucket: 'stemcell-output-bucket',
        vmx_cache_dir: '/tmp',
        endpoint: nil)
        .and_return(s3_vmx)

      allow(Executor).to receive(:exec_command)
      @vhd_version = '20181709'
      @vhd_filename = "some-last-file-Containers-#{@vhd_version}-en.us.vhd"
      s3_client= double(:s3_client)
      allow(s3_client).to receive(:list).and_return([@vhd_filename])
      allow(s3_client).to receive(:get)

      allow(S3::Client).to receive(:new).with(
        endpoint: nil
      ).and_return(s3_client)
    end

    it 'should generate a patchfile and uploads it to Azure' do
      packer_output_vmdk = File.join(@output_directory, 'fake.vmdk')
      expect(packer_output_vmdk).not_to be_nil
      expect(Executor).to receive(:exec_command).with("az storage blob upload "\
        "--container-name #{ENV['AZURE_CONTAINER_NAME']} "\
        "--account-key #{ENV['AZURE_STORAGE_ACCESS_KEY']} "\
        "--name #{@os_version}/untested/patchfile-#{@version}-#{@vhd_version} "\
        "--file #{File.join(File.expand_path(@output_directory), "patchfile-#{@version}-#{@vhd_version}")} "\
        "--account-name #{ENV['AZURE_STORAGE_ACCOUNT_NAME']}")
      Rake::Task['build:vsphere_patchfile'].invoke
    end

    it 'should generate a manifest.yml' do
      Rake::Task['build:vsphere_patchfile'].invoke

      manifest = File.join(@output_directory, "patchfile-#{@version}-#{@vhd_version}.yml")
      expect(File.exist? manifest).to be(true)
      manifest_content = File.read(manifest)
      expect(manifest_content).to include("patch_file: patchfile-#{@version}-#{@vhd_version}")
      expect(manifest_content).to include("os_version: 2016")
      expect(manifest_content).to include("output_dir: .")
      expect(manifest_content).to include("vhd_file: #{@vhd_filename}")
      expect(manifest_content).to include("version: #{@version}")
    end
  end

  describe 'stemcell' do
    before(:each) do
      os_version = 'windows2012R2'
      version = '1200.3.1-build.2'
      agent_commit = 'some-agent-commit'

      ENV['AWS_ACCESS_KEY_ID']= 'some-key'
      ENV['AWS_SECRET_ACCESS_KEY'] = 'secret-key'
      ENV['AWS_REGION'] = 'some-region'
      ENV['INPUT_BUCKET'] = 'input-vmx-bucket'
      ENV['VMX_CACHE_DIR'] = '/tmp'
      ENV['OUTPUT_BUCKET'] = 'stemcell-output-bucket'

      ENV['ADMINISTRATOR_PASSWORD'] = 'pass'
      ENV['PRODUCT_KEY'] = 'product-key'
      ENV['OWNER'] = 'owner'
      ENV['ORGANIZATION'] = 'organization'

      ENV['OS_VERSION'] = os_version
      ENV['VERSION_DIR'] = @version_dir
      ENV['VMX_VERSION_DIR'] = @vmx_version_dir
      ENV['STEMCELL_DEPS_DIR'] = @stemcell_deps_dir
      ENV['PATH'] = "#{File.join(@build_dir, '..', 'spec', 'fixtures', 'vsphere')}:#{ENV['PATH']}"

      FileUtils.mkdir_p(File.join(@build_dir, 'compiled-agent'))
      File.write(
        File.join(@build_dir, 'compiled-agent', 'sha'),
        agent_commit
      )

      File.write(
        File.join(@version_dir, 'number'),
        version
      )
      File.write(
        File.join(@vmx_version_dir, 'number'),
        'some-vmx-version'
      )

      s3_vmx= double(:s3_vmx)
      allow(s3_vmx).to receive(:fetch).and_return("1234")
      allow(s3_vmx).to receive(:put)

      allow(S3::Vmx).to receive(:new).with(
        input_bucket: 'input-vmx-bucket',
        output_bucket: 'stemcell-output-bucket',
        vmx_cache_dir: '/tmp',
        endpoint: nil)
        .and_return(s3_vmx)

      s3_client= double(:s3_client)
      allow(s3_client).to receive(:put)

      allow(S3::Client).to receive(:new).with(
        endpoint: nil
      ).and_return(s3_client)
    end

    it 'should build a vsphere stemcell' do
      Rake::Task['build:vsphere'].invoke

      stembuild_version_arg = JSON.parse(File.read("#{@output_directory}/myargs"))[3]
      expect(stembuild_version_arg).to eq('1200.3.1-build.2')
      stemcell_filename = File.basename(Dir["#{@output_directory}/*.tgz"].first)
      expect(stemcell_filename).to eq "bosh-stemcell-1200.3.1-build.2-vsphere-esxi-windows2012R2-go_agent.tgz"
    end

    context 'when we are not authorized to upload to the S3 bucket' do
      before(:each) do
        allow(S3).to receive(:test_upload_permissions).and_raise(Aws::S3::Errors::Forbidden.new('', ''))
      end

      it 'should fail before building the stemcell' do
        expect do
          Rake::Task['build:vsphere'].invoke
        end.to raise_exception(Aws::S3::Errors::Forbidden)

        files = Dir.glob(File.join(@output_directory, '*').gsub('\\', '/'))
        expect(files).to be_empty
      end
    end
  end
end
