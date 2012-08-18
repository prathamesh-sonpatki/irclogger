class Message < Sequel::Model(:irclog)
  attr_accessor :data

  def type
    if talk?
      "talk"
    elsif me_tell?
      "me-tell"
    elsif info?
      "info"
    end
  end

  def me_tell?
    nick && nick[0] == '*'
  end

  def talk?
    !info? && !me_tell?
  end

  def info?
    nick.nil?
  end

  def self.nicks(messages)
    messages.filter('nick is not null').map(:nick)
  end

  def self.track_chains(messages)
    groups, group_nicks, last = {}, {}, {}
    last_group_id, group_id, current_nick = 0, nil, nil
    prev_group_id = nil
    last_refs = {}

    nicks = nicks(messages)
    messages.to_a.each do |m|
      next unless m.talk?

      nick = nicks.find { |n| m.line.start_with? n }
      if nick || (m.nick != current_nick) || group_id.nil?
        current_nick = m.nick

        if nick
          last_refs[m.nick] = nil
          last_refs[nick] = m.nick
        end

        last_ref = last[last_refs[m.nick]]
        if last_ref && last_ref.line.start_with?(m.nick)
          prev_group_id = groups[nick] || last_ref.data[:group]
        else
          prev_group_id = groups[nick]
        end

        if nick && group_nicks[groups[m.nick]] == nick &&
            (!last[nick] || !last[m.nick] || last[m.nick].timestamp > last[nick].timestamp)
          group_id = groups[m.nick]
        else
          group_id = (last_group_id += 1)
          groups[m.nick] = group_id
          group_nicks[group_id] = nick
        end
      end

      m.data = { :group => group_id, :previous_group => prev_group_id }
      last[m.nick] = m
    end
  end

  def self.find_by_channel_and_date(channel, date)
    day_after = date + 1

    filter('timestamp > ? and timestamp < ?',
                  Time.utc(date.year, date.month, date.day).to_i,
                  Time.utc(day_after.year, day_after.month, day_after.day).to_i).
      filter(:channel => channel).
      order(:timestamp)
  end

  def self.check_by_channel_and_date(channel, date)
    find_by_channel_and_date(channel, date).filter('nick is not null').any?
  end

  def self.check_by_channel_and_month(channel, date)
    from = Time.utc(date.year, date.month, 1)
    to   = Time.utc((date >> 1).year, (date >> 1).month, 1) - 1
    filter('timestamp > ? and timestamp < ?', from.to_i, to.to_i).
        filter(:channel => channel).any?
  end

  def self.find_by_channel_and_fulltext(channel, query)
    order(:timestamp).filter(:channel => channel).filter('nick is not null').
           filter('match (nick, line) against (? in boolean mode)', query)
  end

  def self.any_recent_messages?(interval = 600)
    filter('timestamp > ?', Time.now.to_i - interval).any?
  end
end
