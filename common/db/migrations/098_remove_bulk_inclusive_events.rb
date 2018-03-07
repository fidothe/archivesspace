require_relative 'utils'

Sequel.migration do

  up do
    enum = self[:enumeration].filter(:name => 'date_type').select(:id)
    range = self[:enumeration_value].filter(:value => 'range').select(:id)

    # Changing all event dates that are bulk dates to ranges
    bulk_date = self[:enumeration_value].filter(:value => "bulk").select(:id)
    self[:date].exclude(:event_id => nil).filter(:date_type_id => bulk_date).update(:date_type_id => range)

    # Changing all event dates that are inclusive dates to ranges
    inclusive_date = self[:enumeration_value].filter(:value => "inclusive").select(:id)
    self[:date].exclude(:event_id => nil).filter(:date_type_id => inclusive_date).update(:date_type_id => range)

  end

end
