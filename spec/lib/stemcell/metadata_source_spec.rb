require 'spec_helper'

describe Stemcell::MetadataSource do

  let(:chef_root)       { FixtureHelper.chef_repo_fixture_path }
  let(:config_filename) { 'stemcell.json' }

  let(:metadata_source) do
    Stemcell::MetadataSource.new(chef_root, config_filename)
  end

  let(:config) { metadata_source.config }
  let(:chef_repo) { metadata_source.chef_repo }

  describe '#initialize' do

    context "when the arguments are valid" do
      it "sets chef_root" do
        expect(metadata_source.chef_root).to eql chef_root
      end
      it "sets config_filename" do
        expect(metadata_source.config_filename).to eql config_filename
      end

      it "constructs a configuration object" do
        expect(metadata_source.config).to be_an_instance_of(
          Stemcell::MetadataSource::Configuration)
      end

      it "uses the correct path for the configuration object" do
        expect(metadata_source.config.config_path).to eql(
          File.join(chef_root, config_filename))
      end

      it "constructs a chef repository object" do
        expect(metadata_source.chef_repo).to be_an_instance_of(
          Stemcell::MetadataSource::ChefRepository)
      end

      it "uses the correct path for the chef repository object" do
        expect(metadata_source.chef_repo.chef_root).to eql(chef_root)
      end
    end

    context "when the chef root is nil" do
      let(:chef_root) { nil }
      it "raises an ArgumentError" do
        expect { metadata_source }.to raise_error(ArgumentError)
      end
    end

    context "when the configuration file name is nil" do
      let(:config_filename) { nil }
      it "raise an ArgumentError" do
        expect { metadata_source }.to raise_error(ArgumentError)
      end
    end

  end

  describe '#expand_role' do

    let(:default_options)    { Hash.new }
    let(:backing_options)    { Hash.new }
    let(:availability_zones) { Hash.new }
    let(:role_metadata)      { Hash.new }
    let(:override_options)   { Hash.new }
    let(:expand_options)     { Hash.new }

    before do
      config.stub(:default_options) { default_options }
      config.stub(:availability_zones) { availability_zones }
      config.stub(:options_for_backing_store) { backing_options }
      chef_repo.stub(:metadata_for_role) { role_metadata }
    end

    let(:role)        { 'role' }
    let(:environment) { 'production' }

    let(:expansion) do
      metadata_source.expand_role(
        role,
        environment,
        override_options,
        expand_options)
    end

    context "when arguments are valid" do

      before { role_metadata.merge!('instance_type' => 'c1.xlarge') }

      describe "backing store" do

        context "when backing store is not explicitly set" do
          it "uses instance_store" do
            expect(expansion['backing_store']).to eql 'instance_store'
          end
        end

        context "when the override options specify a backing store" do
          before { override_options.merge!('backing_store' => 'from_override') }

          it "is the value in the override options" do
            expect(expansion['backing_store']).to eql 'from_override'
          end

          it "overrides the backing store set in the role" do
            role_metadata.merge!('backing_store' => 'from_role')
            expect(expansion['backing_store']).to eql 'from_override'
          end
        end

        context "when the role metadata specifies a backing store" do
          before { role_metadata.merge!('backing_store' => 'from_role') }

          it "is the value in the role metadata" do
            expect(expansion['backing_store']).to eql 'from_role'
          end

          it "overrides the value given in the configuration" do
            default_options.merge!('backing_store' => 'from_defaults')
            expect(expansion['backing_store']).to eql 'from_role'
          end
        end

        context "when the default options specify a backing store" do
          before { default_options.merge!('backing_store' => 'from_defaults') }

          it "is the value in the default options" do
            expect(expansion['backing_store']).to eql 'from_defaults'
          end
        end

      end

      describe 'expansion' do

        context "when no options are explicitly set" do
          it "contains the defaults" do
            # This assumes that the environment is set to the default
            Stemcell::MetadataSource::DEFAULT_OPTIONS.each_pair do |key, value|
              expect(expansion[key]).to eql value
            end
          end
        end

        context "when the role and environment are not the default" do
          let(:role)        { 'not_default_role' }
          let(:environment) { 'not_default_environmnet' }

          it "contains the role" do
            expect(expansion['chef_role']).to eql role
          end
          it "contains the environment" do
            expect(expansion['chef_environment']).to eql environment
          end
        end

        it "calls the config object to retrieve the backing store options" do
          backing_options.merge!('image_id' => 'ami-nyancat')
          override_options.merge!('backing_store' => 'ebs')
          config.should_receive(:options_for_backing_store).with('ebs') { backing_options }
          expect(expansion['image_id']).to eql 'ami-nyancat'
        end

        it "calls the repository object to determine the role metadata" do
          role_metadata.merge!('image_id' => 'ami-nyancat')
          chef_repo.should_receive(:metadata_for_role).with(role, environment) { role_metadata }
          expect(expansion['image_id']).to eql 'ami-nyancat'
        end

        context "when a config default overrides a built-in default" do
          before { default_options.merge!('git_branch' => 'from_default') }

          it "returns the value from the config defaults" do
            expect(expansion['git_branch']).to eql 'from_default'
          end
        end

        context "when role metadata overrides a config default" do
          before { default_options.merge!('option' => 'from_default') }
          before { role_metadata.merge!('option' => 'from_role') }

          it "returns the value from the role metadata" do
            expect(expansion['option']).to eql 'from_role'
          end
        end

        context "when an override option overrides the role metadata" do
          before { role_metadata.merge!('option' => 'from_role') }
          before { override_options.merge!('option' => 'from_override') }

          it "returns the value from the override options" do
            expect(expansion['option']).to eql 'from_override'
          end
        end

        context "when a region was specified but no availability zone" do

          let(:availability_zones) { { 'us-east-1' => ['us-east-1a'] } }

          before do
            override_options.merge!('region' => 'us-east-1')
            override_options.merge!('availability_zone' => nil)
          end

          it "substitutes an availability zone from the config" do
            expect(expansion['availability_zone']).to eql 'us-east-1a'
          end
        end

      end

    end

    context "when the role metadata isn't present" do
      let(:role_metadata) { nil }

      context "when allowing empty roles" do
        before { expand_options[:allow_empty_roles] = true }
        it "returns successfully" do
          expect(expansion).to_not be_nil
        end
      end

      context "when not allowing empty roles" do
        before { expand_options[:allow_empty_roles] = false }
        it "raises" do
          expect { expansion }.to raise_error(Stemcell::EmptyRoleError)
        end
      end
    end

    context "when role is nil" do
      let(:role) { nil }
      it "raises" do
        expect { expansion }.to raise_error(ArgumentError)
      end
    end

    context "when environment is nil" do
      let(:environment) { nil }
      it "raises" do
        expect { expansion }.to raise_error(ArgumentError)
      end
    end

  end

end