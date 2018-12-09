module Services
  # This singleton service manages the different instances of websockets associated to the different users.
  # @author Vincent Courtois <courtois.vincent@outlook.com>
  class Repartitor
    include Singleton

    attr_accessor :logger

    def initialize
      @logger = Logger.new(STDOUT)
    end

    # Forwards the message by finding if it's for a campaign, a user, or several users.
    # @param params [Hash] an object containing all the needed properties for the message to be forwarded.
    def forward_message(session, params)
      if !params['account_id'].nil?
        send_to_account(session, params['account_id'], params['message'], params['data'] || {})
      elsif !params['account_ids'].nil?
        send_to_accounts(session, params['account_ids'], params['message'], params['data'] || {})
      elsif !params['campaign_id'].nil?
        send_to_campaign(session, params['campaign_id'], params['message'], params['data'] || {})
      elsif !params['username'].nil?
        send_to_username(session, params['username'], params['message'], params['data'])
      end
    end

    # Forwards a request to all the sessions needing it.
    # @param session [Arkaan::Authentication::Session] the session of the account making the notification to the other accounts.
    # @param sessions [Array<Arkaan::Authentication::Session>] the sessions you want to notify.
    # @param message [String] the action of the message.
    # @param data [Hash] a hash of additional data to send with the message.
    def send_to_sessions(session, sessions, message, data)
      service = Arkaan::Monitoring::Service.where(key: 'websockets').first
      if !service.nil?
        logger.info("Les sessions en mode brut sont : #{sessions.pluck(:_id).map(&:to_s).join(', ')}")
        grouped = sessions.group_by { |session| session.websocket_id }
        grouped.each do |websocket_id, sessions|
          logger.info("Envoi au websocket #{websocket_id} des notifications pour #{sessions.pluck(:_id)}")
          send_to_websocket(session, websocket_id, sessions.pluck(:_id).map(&:to_s), message, data)
        end
      end
    end

    # Sends the message to the given instance of the websockets service, and to the given sessions.
    # @param session [Arkaan::Authentication::Session] the session of the account making the notification to the other accounts.
    # @param instance_id [ObjectId] the unique identifier of the instance to reach.
    # @param sessions [Array<Arkaan::Authentication::Session>] the sessions you want to notify.
    # @param message [String] the action of the message.
    # @param data [Hash] a hash of additional data to send with the message.
    def send_to_websocket(session, instance_id, session_ids, message, data)
      parameters = {
        session: session,
        url: '/websockets/messages',
        params: {
          session_ids: session_ids,
          instance_id: instance_id,
          message: message,
          data: data
        }
      }
      logger.info(parameters.to_json)
      Arkaan::Factories::Gateways.random('messages').post(parameters)
    end

    # Sends a message to all the connected sessions of a user so that he sees it on all its terminals.
    # @param account_id [String] the uniq identifier of the account you're trying to reach.
    # @param message [String] the type of message you want to send.
    # @param data [Hash] a JSON-compatible hash to send as a JSON string with the message type.
    def send_to_account(session, account_id, message, data)
      account = Arkaan::Account.where(_id: account_id).first
      raise Services::Exceptions::ItemNotFound.new('account_id') if account.nil?
      send_to_sessions(session, account.sessions, message, data)
    end

    # Sends a message to all the users of a campaign (all accepted or creator invitations in the campaign)
    # @param campaign_id [String] the uniq identifier of the campaign.
    # @param message [String] the type of message you want to send.
    # @param data [Hash] a JSON-compatible hash to send as a JSON string with the message type.
    def send_to_campaign(session, campaign_id, message, data)
      campaign = Arkaan::Campaign.where(_id: campaign_id).first
      raise Services::Exceptions::ItemNotFound.new('campaign_id') if campaign.nil?
      logger.info("Envoi d'un message à tous les compte de la campagne #{campaign.title}")
      invitations = campaign.invitations.where(:enum_status.in => ['creator', 'accepted'])
      sessions = Arkaan::Authentication::Session.where(:account_id.in => campaign.invitations.pluck(:account_id), :id.ne => session.id)
      send_to_sessions(session, sessions, message, data)
    end

    # Sends a message to all users in a list of accounts.
    # @param account_ids [Array<String>] the uniq identifiers of the accounts you're trying to reach.
    # @param message [String] the type of message you want to send.
    # @param data [Hash] a JSON-compatible hash to send as a JSON string with the message type.
    def send_to_accounts(session, account_ids, message, data)
      account_ids.each do |account_id|
        account = Arkaan::Account.where(_id: account_id).first
        raise Services::Exceptions::ItemNotFound.new('account_id') if account.nil?
      end
      sessions = Arkaan::Authentication::Session.where(:account_id.in => account_ids)
      send_to_sessions(session, sessions, message, data)
    end

    def send_to_username(session, username, message, data)
      account = Arkaan::Account.where(username: username).first
      raise Services::Exceptions::ItemNotFound.new('username') if account.nil?
      send_to_sessions(session, account.sessions, message, data)
    end
  end
end