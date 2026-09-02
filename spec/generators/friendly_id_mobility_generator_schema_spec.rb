require "spec_helper"
require "generators/friendly_id_mobility_generator"
require "generator_spec/test_case"
require "open3"
require "rbconfig"

describe FriendlyIdMobilityGenerator, type: :generator do
  include GeneratorSpec::TestCase

  destination File.expand_path("../tmp/schema_generator", __FILE__)

  before(:all) do
    prepare_destination
    run_generator
  end

  after(:all) do
    prepare_destination
  end

  def generated_migration
    Dir[
      File.join(
        destination_root,
        "db/migrate/*_add_locale_to_friendly_id_slugs.rb"
      )
    ].fetch(0)
  end

  def schema_probe
    <<~RUBY
      require "active_record"

      ActiveRecord::Migration.verbose = false

      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: ":memory:"
      )

      ActiveRecord::Schema.define do
        create_table :friendly_id_slugs do |t|
          t.string :slug, null: false
          t.integer :sluggable_id, null: false
          t.string :sluggable_type, limit: 50
          t.string :scope
          t.datetime :created_at
        end

        add_index :friendly_id_slugs,
          [:sluggable_type, :sluggable_id]

        add_index :friendly_id_slugs,
          [:slug, :sluggable_type]

        add_index :friendly_id_slugs,
          [:slug, :sluggable_type, :scope],
          unique: true
      end

      load #{generated_migration.dump}

      AddLocaleToFriendlyIdSlugs.new.migrate(:up)

      connection = ActiveRecord::Base.connection

      locale = connection
        .columns(:friendly_id_slugs)
        .find { |column| column.name == "locale" }

      abort "locale column missing" unless locale

      puts "locale|null=\#{locale.null}"

      indexes = connection.indexes(:friendly_id_slugs)

      indexes.each do |index|
        puts [
          "index",
          index.name,
          index.unique,
          index.columns.join(",")
        ].join("|")
      end

      exit(locale.null == false ? 0 : 41)
    RUBY
  end

  it "generates a NOT NULL locale column when the migration is executed" do
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-e",
      schema_probe
    )

    expect(status.exitstatus).to eq(0), -> {
      [stdout, stderr].join("\n")
    }

    expect(stdout).to include("locale|null=false")
  end

  it "generates locale-aware history indexes when the migration is executed" do
    stdout, stderr, _status = Open3.capture3(
      RbConfig.ruby,
      "-e",
      schema_probe
    )

    aggregate_failures do
      expect(stderr).to eq("")

      expect(stdout).to include(
        "slug,sluggable_type,locale"
      )

      expect(stdout).to include(
        "slug,sluggable_type,scope,locale"
      )

      expect(stdout).to match(
        /index\|index_friendly_id_slugs_unique\|true\|/
      )
    end
  end
end
