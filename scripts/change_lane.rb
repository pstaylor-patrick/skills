#!/usr/bin/env ruby
# frozen_string_literal: true

# Shared base for the four change-fabric lanes. It owns the two things every lane
# resolves the same way: the base url a lane addresses the target by (a per-lane
# override falling back to the run's target), and the route list (falling back to
# the site root). A lane subclass supplies its own DEFAULT_ROUTES only when the
# root is not a sensible default; otherwise it inherits this one. Keeping these
# here means a change to how a lane picks its target propagates to all of them
# instead of drifting between copies.
class ChangeLane
  DEFAULT_ROUTES = %w[/].freeze

  def initialize(config, context)
    @config = config
    @context = context
  end

  private

  def base_url = @config.base_url(@context.target_url)

  def routes
    list = Array(@config['routes']).map(&:to_s).reject(&:empty?)
    list.empty? ? self.class::DEFAULT_ROUTES : list
  end
end
