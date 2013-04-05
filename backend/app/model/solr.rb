require 'uri'
require 'net/http'


class Solr

  def self.solr_url
    URI.parse(AppConfig[:solr_url])
  end


  def self.search(query, page, page_size, repo_id,
                  record_types = nil, show_suppressed = false,
                  excluded_ids = [], extra_solr_params = {})
    url = solr_url

    opts = {
      :q => query,
      :wt => "json",
      :defType => "edismax",
      :qf => "title^2 fullrecord",
      :start => (page - 1) * page_size,
      :rows => page_size,
    }.to_a

    extra_solr_params.each { |k,v|
      Array(v).each {|val| opts << [k, val]}
    }

    opts << ["facet", true] if extra_solr_params.has_key?("facet.field")

    if repo_id
      opts << [:fq, "repository:\"/repositories/#{repo_id}\" OR repository:global"]
    end

    if record_types
      query = record_types.map { |type| "\"#{type}\"" }.join(' OR ')
      opts << [:fq, "types:(#{query})"]
    end

    if !show_suppressed
      opts << [:fq, "suppressed:false"]
    end

    if excluded_ids && !excluded_ids.empty?
      query = excluded_ids.map { |id| "\"#{id}\"" }.join(' OR ')
      opts << [:fq, "-id:(#{query})"]
    end

    url.path = "/select"
    url.query = URI.encode_www_form(opts)

    req = Net::HTTP::Get.new(url.request_uri)

    Net::HTTP.start(url.host, url.port) do |http|
      solr_response = http.request(req)

      if solr_response.code == '200'
        json = ASUtils.json_parse(solr_response.body)

        result = {}

        result['first_page'] = 1
        result['last_page'] = (json['response']['numFound'] / page_size.to_f).floor + 1
        result['this_page'] = (json['response']['start'] / page_size) + 1

        result['offset_first'] = json['response']['start'] + 1
        result['offset_last'] = [(json['response']['start'] + page_size), json['response']['numFound']].min
        result['total_hits'] = json['response']['numFound']

        result['results'] = json['response']['docs'].map {|doc|
          doc['uri'] = doc['id']
          doc['jsonmodel_type'] = doc['primary_type']
          doc
        }

        result['facets'] = json['facet_counts']

        return result
      else
        raise "Solr search failed: #{solr_response.body}"
      end
    end
  end


  def self.expire_snapshots
    backups = []
    backups_dir = AppConfig[:solr_backup_directory]

    Dir.foreach(backups_dir) do |filename|
      if filename =~ /^solr\.[0-9]+$/
        backups << File.join(backups_dir, filename)
      end
    end

    victims = backups.sort.reverse.drop(AppConfig[:solr_backup_number_to_keep])

    victims.each do |backup_dir|

      if File.exists?(File.join(backup_dir, "indexer_state"))
        Log.info("Expiring old Solr snapshot: #{backup_dir}")
        FileUtils.rm_rf(backup_dir)
      else
        Log.warn("Too cowardly to delete: #{backup_dir}")
      end
    end

  end



  def self.snapshot
    timestamp = Time.now.to_i

    target = File.join(AppConfig[:solr_backup_directory], "solr.#{timestamp}")

    FileUtils.mkdir_p(target)

    FileUtils.cp_r(File.join(AppConfig[:data_directory], "indexer_state"),
                   target)

    response = Net::HTTP.get_response(URI.join(AppConfig[:solr_url],
                                               "/replication?command=backup&numberToKeep=1"))

    if response.code == '200'
      latest = Dir.glob(File.join(AppConfig[:solr_index_directory], "snapshot.*")).sort.last

      FileUtils.mv(latest, target)

      self.expire_snapshots
    end
  end

end