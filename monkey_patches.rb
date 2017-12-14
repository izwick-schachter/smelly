module ChatX
  class Message
    attr_reader :server, :timestamp, :content, :room, :user, :id, :parent_id

    def initialize(server, **opts)
      if opts.values_at(:time_stamp, :content, :room_id, :user_id, :message_id).any?(&:nil?)
        puts "Bad error about to happen. Tryna create from #{opts} #{opts.class} #{opts.inspect}"
        raise ChatX::InitializationDataException, 'Got nil for an expected message property'
      end

      @server = server

      @id = opts[:message_id]
      @timestamp = Time.at(opts[:time_stamp]).utc.to_datetime
      @content = opts[:content]
      @room = ChatX::Helpers.cached opts[:room_id].to_i, :rooms do
        ChatX::Room.new server, room_id: opts[:room_id].to_i
      end
      @user = ChatX::Helpers.cached opts[:user_id].to_i, :users do
        ChatX::User.new server, user_id: opts[:user_id].to_i
      end

      @parent_id = opts[:parent_id]
    end
  end
end

=begin
class ChatBot
  # The immediate exit point when a message is recieved from a websocket. It
  # grabs the relevant hooks, creates the event, and passes the event to the
  # hooks.
  #
  # It also spawns a new thread for every hook. This could lead to errors later,
  # but it prevents 409 errors which shut the bot up for a while.
  #
  # @note This method is strictly internal.
  # @param data [Hash] It's the JSON passed by the websocket
  def handle(data, server: @default_server)
    data.each do |room, evt|
      next if evt.keys.first != 'e'
      evt['e'].each do |e|
        event_type = e['event_type'].to_i - 1
        room_id = room[1..-1].to_i
        event = ChatX::Event.new e, server, self
        @logger.info "#{event.type_long}: #{event.hash} #{event.message.inspect}"
        @logger.info "Currently in rooms #{@rooms.keys} / #{current_rooms}"
        break if @rooms[room_id].nil?
        @rooms[room_id.to_i][:events].push(event)
        next if @hooks[event_type.to_i].nil?
        @hooks[event_type.to_i].each do |rm_id, hook|
          #Thread.new do
            @hook.current_room = room_id
            hook.call(event) if rm_id == room_id || rm_id == '*'
          #end
        end
      end
    end
  end
end
=end
