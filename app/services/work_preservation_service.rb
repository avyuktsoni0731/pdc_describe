# frozen_string_literal: true

# A service to create and store the preservation data for a given work.
# Currently it assumes this data will be stored in an AWS S3 bucket accessible
# with our AWS credentials, but allows the bucket and path to be configurable.
class WorkPreservationService

  # @param work_id [Integer] The ID of the work to preserve.
  # @param bucket_name [String] The AWS S3 bucket name where the work will be preserved.
  # @param path [String] The path where the work will be preserved.
  def initialize(work_id:, bucket_name:, path:)
    @work = Work.find(work_id)
    @bucket_name = bucket_name
    @path = path
  end

  # Creates and stores the preservation files for the work.
  # @return [String] The AWS S3 path where the files were stored
  def preserve!
    create_preservation_directory
    upload_file(io: metadata_io, filename: "metadata.json")
    upload_file(io: datacite_io, filename: "datacite.xml")
    Rails.logger.info "Preservation files for work #{@work.id} saved to #{target_location}"
    target_location
  end

  private

    def target_location
      "s3://#{@bucket_name}/#{preservation_directory}"
    end

    def metadata_io
      # Always use the post-curation file list
      StringIO.new(@work.to_json(force_post_curation: true))
    end

    def datacite_io
      StringIO.new(@work.to_xml)
    end

    def preservation_directory
      Pathname.new(@path).join("princeton_data_commons/")
    end

    def s3_client
      @work.s3_query_service.client
    end

    def create_preservation_directory
      s3_client.put_object({ bucket: @bucket_name, key: preservation_directory.to_s, content_length: 0 })
    end

    def upload_file(io:, filename:)
      md5_digest = @work.s3_query_service.md5(io:)
      key = preservation_directory.join(filename).to_s
      s3_client.put_object(bucket: @bucket_name, key: key, body: io, content_md5: md5_digest)
      key
    end
end
