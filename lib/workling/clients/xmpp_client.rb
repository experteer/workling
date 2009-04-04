require 'workling/clients/base'
Workling.try_load_xmpp4r

#
#  An XMPP client
#
#  How to use: this client requires the xmpp4r gem
#
#  in the config/environments/development.rb file (or production.rb etc)
#
#    Workling::Remote::Runners::ClientRunner.client = Workling::Clients::XmppClient.new
#    Workling::Remote.dispatcher = Workling::Remote::Runners::ClientRunner.new        # dont use the standard runner
#    Workling::Remote.invoker = Workling::Remote::Invokers::LoopedSubscriber          # does not work with the EventmachineSubscriber Invoker
#
#  furthermore in the workling.yml file you need to set up the server details for your XMPP server
#
#    development:
#      listens_on: "localhost:22122"
#      jabber_id: "sub@localhost/laptop"
#      jabber_server: "localhost"
#      jabber_password: "sub"
#      jabber_service: "pubsub.derfredtop.local"
#
#  for details on how to configure your XMPP server (ejabberd) check out the following howto:
#
#    http://keoko.wordpress.com/2008/12/17/xmpp-pubsub-with-ejabberd-and-xmpp4r/
#
#
#  finally you need to expose your worker methods to XMPP nodes like so:
# 
#    class NotificationWorker < Workling::Base
# 
#      expose :receive_notification, :as => "/home/localhost/pub/sub"
# 
#      def receive_notification(input)
#        # something here
#      end
# 
#    end
#



module Workling
  module Clients
    class XmppClient < Workling::Clients::Base

      # starts the client. 
      def connect
        begin
          @client = Jabber::Client.new Workling.config[:jabber_id]
          @client.connect Workling.config[:jabber_server]
          @client.auth Workling.config[:jabber_password]
          @client.send Jabber::Presence.new.set_type(:available)
          @pubsub = Jabber::PubSub::ServiceHelper.new(@client, Workling.config[:jabber_service])
          unsubscribe_from_all                # make sure there are no open subscriptions, could cause multiple delivery of notifications, as they are persistent
        rescue
          raise WorklingError.new("couldn't connect to the jabber server")
        end
      end

      # disconnect from the server
      def close
        @client.close
      end

      # subscribe to a queue
      def subscribe(key)
        @pubsub.subscribe_to(key)

        # filter out the subscription notification message that was generated by subscribing to the node
        @pubsub.get_subscriptions_from_all_nodes()

        @pubsub.add_event_callback do |event|
          event.payload.each do |e|
            e.children.each do |child|
              yield Hash.from_xml(child.children.first.to_s) if child.name == 'item'
            end
          end
        end
      end

      # request and retrieve work
      def retrieve(key)
        @pubsub.get_items_from(key, 1)
      end

      def request(key, value)
        @pubsub.publish_item_to(key, value)
      end

      private
        def unsubscribe_from_all
          @pubsub.get_subscriptions_from_all_nodes.each do |subscription|
            @pubsub.unsubscribe_from subscription.node
          end
        end
    end
  end
end
