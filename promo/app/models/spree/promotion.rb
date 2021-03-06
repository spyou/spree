module Spree
  class Promotion < Spree::Activator
    MATCH_POLICIES = %w(all any)

    has_many :promotion_rules, :foreign_key => 'activator_id', :autosave => true, :dependent => :destroy
    alias_method :rules, :promotion_rules
    accepts_nested_attributes_for :promotion_rules

    has_many :promotion_actions, :foreign_key => 'activator_id', :autosave => true, :dependent => :destroy
    alias_method :actions, :promotion_actions
    accepts_nested_attributes_for :promotion_actions

    # TODO: This shouldn't be necessary with :autosave option but nested attribute updating of actions is broken without it
    after_save :save_rules_and_actions
    def save_rules_and_actions
      (rules + actions).each &:save
    end

    validates :name, :presence => true
    validates :code, :presence => true, :if => lambda{|r| r.event_name == 'spree.checkout.coupon_code_added' }
    validates :usage_limit, :numericality => { :greater_than => 0, :allow_nil => true }

    class << self
      def advertised
        #TODO this is broken because the new preferences aren't a direct relationship returning
        #all for now
        scoped
        #includes(:stored_preferences)
        #includes(:stored_preferences).where(:spree_preferences => {:name => 'advertise', :value => '1'})
      end
    end

    # TODO: Remove that after fix for https://rails.lighthouseapp.com/projects/8994/tickets/4329-has_many-through-association-does-not-link-models-on-association-save
    # is provided
    def save(*)
      if super
        promotion_rules.each { |p| p.save }
      end
    end

    def activate(payload)
      if code.present?
        event_code = payload[:coupon_code].to_s.strip.downcase
        return unless event_code == self.code.to_s.strip.downcase
      end

      actions.each do |action|
        action.perform(payload)
      end
    end

    # called anytime order.update! happens
    def eligible?(order)
      return false if expired? || usage_limit_exceeded?(order)
      rules_are_eligible?(order, {})
    end

    def rules_are_eligible?(order, options = {})
      return true if rules.none?
      eligible = lambda { |r| r.eligible?(order, options) }
      if match_policy == 'all'
        rules.all?(&eligible)
      else
        rules.any?(&eligible)
      end
    end

    # Products assigned to all product rules
    def products
      @products ||= rules.of_type('Promotion::Rules::Product').map(&:products).flatten.uniq
    end

    def usage_limit_exceeded?(order = nil)
      usage_limit.present? && usage_limit > 0 && adjusted_credits_count(order) >= usage_limit
    end

    def adjusted_credits_count(order)
      return credits_count if order.nil?
      credits_count - (order.promotion_credit_exists?(self) ? 1 : 0)
    end

    def credits
      Adjustment.promotion.where(:originator_id => actions.map(&:id))
    end

    def credits_count
      credits.count
    end

  end
end
