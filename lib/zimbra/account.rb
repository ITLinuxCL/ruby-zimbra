module Zimbra
  class Account
    class << self
      def all(options = {})
        AccountService.all(options)
      end

      def find_by_id(id)
        AccountService.get_by_id(id)
      end

      def find_by_name(name)
        AccountService.get_by_name(name)
      end

      def create(options)
        account = new(options)
        AccountService.create(account)
      end

      def acl_name
        'account'
      end
    end

    attr_accessor :id, :name, :password, :acls, :cos_id, :delegated_admin
    attr_accessor :mail_quota # in bytes
    attr_accessor :status

    # readonly attributes
    attr_accessor :created_at, :last_login_at

    def initialize(options = {})
      self.id = options[:id]
      self.name = options[:name]
      self.password = options[:password]
      self.acls = options[:acls] || []
      self.cos_id = (options[:cos] ? options[:cos].id : options[:cos_id])
      self.delegated_admin = options[:delegated_admin]
      self.mail_quota = options[:mail_quota]
      self.status = options[:status]
      self.created_at = options[:created_at]
      self.last_login_at = options[:last_login_at]
    end

    def delegated_admin=(val)
      @delegated_admin = Zimbra::Boolean.read(val)
    end
    def delegated_admin?
      @delegated_admin
    end

    def save
      AccountService.modify(self)
    end

    def delete
      AccountService.delete(self)
    end
  end

  class AccountService < HandsoapService
    def all(options = {})
      xml = invoke("n2:GetAllAccountsRequest") do |message|
        if options[:by_domain]
          message.add 'domain', options[:by_domain] do |c|
            c.set_attr 'by', 'name'
          end
        end
      end
      Parser.get_all_response(xml)
    end

    def create(account)
      xml = invoke("n2:CreateAccountRequest") do |message|
        Builder.create(message, account)
      end
      Parser.account_response(xml/"//n2:account")
    end

    def get_by_id(id)
      xml = invoke("n2:GetAccountRequest") do |message|
        Builder.get_by_id(message, id)
      end
      return nil if soap_fault_not_found?
      Parser.account_response(xml/"//n2:account")
    end

    def get_by_name(name)
      xml = invoke("n2:GetAccountRequest") do |message|
        Builder.get_by_name(message, name)
      end
      return nil if soap_fault_not_found?
      Parser.account_response(xml/"//n2:account")
    end

    def modify(account)
      xml = invoke("n2:ModifyAccountRequest") do |message|
        Builder.modify(message, account)
      end
      Parser.account_response(xml/'//n2:account')
    end

    def delete(dist)
      xml = invoke("n2:DeleteAccountRequest") do |message|
        Builder.delete(message, dist.id)
      end
    end

    class Builder
      class << self
        def create(message, account)
          message.add 'name', account.name
          message.add 'password', account.password
          A.inject(message, 'zimbraCOSId', account.cos_id)
          A.inject(message, 'zimbraMailQuota', account.mail_quota)
        end

        def get_by_id(message, id)
          message.add 'account', id do |c|
            c.set_attr 'by', 'id'
          end
        end

        def get_by_name(message, name)
          message.add 'account', name do |c|
            c.set_attr 'by', 'name'
          end
        end

        def modify(message, account)
          message.add 'id', account.id
          modify_attributes(message, account)
        end
        def modify_attributes(message, account)
          if account.acls.empty?
            ACL.delete_all(message)
          else
            account.acls.each do |acl|
              acl.apply(message)
            end
          end
          Zimbra::A.inject(message, 'zimbraCOSId', account.cos_id)
          Zimbra::A.inject(message, 'zimbraIsDelegatedAdminAccount', (account.delegated_admin? ? 'TRUE' : 'FALSE'))
          Zimbra::A.inject(message, 'zimbraMailQuota', account.mail_quota)
          if self.status
            Zimbra::A.inject(message, 'zimbraAccountStatus', account.status)
          end
        end

        def delete(message, id)
          message.add 'id', id
        end
      end
    end
    class Parser
      class << self
        def get_all_response(response)
          (response/"//n2:account").map do |node|
            account_response(node)
          end
        end

        def account_response(node)
          id = (node/'@id').to_s
          name = (node/'@name').to_s
          acls = Zimbra::ACL.read(node)
          cos_id = Zimbra::A.read(node, 'zimbraCOSId')
          delegated_admin = Zimbra::A.read(node, 'zimbraIsDelegatedAdminAccount')
          mail_quota = Zimbra::A.single_read(node, 'zimbraMailQuota').to_i
          status = Zimbra::A.single_read(node, 'zimbraAccountStatus')
          created_at = DateTime.parse(Zimbra::A.single_read(node, 'zimbraCreateTimestamp'))
          last_login_at = Zimbra::A.single_read(node, 'zimbraLastLogonTimestamp')
          if last_login_at && !last_login_at.empty?
            last_login_at = DateTime.parse(last_login_at)
          end
          Zimbra::Account.new(
            :id => id,
            :name => name,
            :acls => acls,
            :cos_id => cos_id,
            :delegated_admin => delegated_admin,
            :mail_quota => mail_quota,
            :status => status,
            :created_at => created_at,
            :last_login_at => last_login_at,
          )
        end
      end
    end
  end
end
