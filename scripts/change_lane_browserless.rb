#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'change_lane'
require_relative 'change_findings'

# The browserless UX/responsive lane. Loads each route at each configured
# viewport in the shared browserless Chromium container and asserts the baseline
# responsive-health checks a manual multi-viewport pass would look for: the page
# navigated without an error status, and it does not overflow horizontally (a
# body wider than the viewport is the classic responsive break). A navigation
# error or horizontal overflow is a fail; page console errors are a warn.
#
# This is the deterministic, config-driven counterpart to the AMFM
# apps/e2e/src/smoke.ts / full.ts Playwright-over-CDP harness: same ephemeral
# browserless container, but a fixed responsive rubric across a viewport matrix
# rather than hand-authored flow assertions.
class ChangeLaneBrowserless < ChangeLane
  DEFAULT_VIEWPORTS = [
    { 'name' => 'mobile', 'width' => 390, 'height' => 844 },
    { 'name' => 'tablet', 'width' => 768, 'height' => 1024 },
    { 'name' => 'desktop', 'width' => 1440, 'height' => 900 }
  ].freeze

  def run
    session = @context.browserless
    return [ unavailable ] unless session

    result = session.run_function(scan_module)
    Array(result).map { |check| check_finding(check) }
  rescue StandardError => e
    [ Finding.new(lane: 'browserless', check: 'viewport scan', status: 'fail', severity: 'high',
                  detail: "scan error: #{e.message}") ]
  end

  private

  def viewports = (@config['viewports'] || DEFAULT_VIEWPORTS)

  def check_finding(check)
    status, severity, detail = grade(check)
    Finding.new(lane: 'browserless', check: "#{check['viewport']} #{check['width']}x#{check['height']}",
                target: base_url, status: status, severity: severity,
                location: check['route'].to_s, detail: detail)
  end

  def grade(check)
    return [ 'fail', 'high', "navigation error: #{check['error']}" ] if check['error']
    return [ 'fail', 'high', "http #{check['httpStatus']}" ] if bad_status?(check['httpStatus'])

    served = redirected_path(check['route'], check['finalUrl'])
    if served
      return [ 'warn', 'low',
               "requested #{check['route']}, redirected to #{served}; the viewport checks reflect that page, not the requested route" ]
    end

    return [ 'fail', 'medium', "horizontal overflow: scrollWidth #{check['scrollWidth']} > #{check['width']}" ] if check['overflow']
    return [ 'warn', 'low', "#{check['consoleErrors']} console error(s)" ] if check['consoleErrors'].to_i.positive?

    [ 'pass', 'info', 'no responsive break' ]
  end

  def bad_status?(status) = status && status.to_i >= 400

  def unavailable
    Finding.new(lane: 'browserless', check: 'browserless', status: 'fail', severity: 'high',
                detail: 'browserless session unavailable; cannot run viewport checks')
  end

  # One module walks the viewport-by-route matrix. For each cell it sets the
  # viewport, navigates, records the response status, counts page console errors,
  # and measures horizontal overflow, returning one flat entry per cell.
  def scan_module
    <<~JS
      export default async function ({ page }) {
        const baseUrl = #{JSON.generate(base_url)};
        const routes = #{JSON.generate(routes)};
        const viewports = #{JSON.generate(viewports)};
        const out = [];
        for (const vp of viewports) {
          for (const route of routes) {
            const cell = { viewport: vp.name, width: vp.width, height: vp.height, route };
            let consoleErrors = 0;
            const onError = (msg) => { if (msg.type() === "error") consoleErrors += 1; };
            page.on("console", onError);
            try {
              await page.setViewport({ width: vp.width, height: vp.height });
              const resp = await page.goto(baseUrl + route, { waitUntil: "networkidle2", timeout: 30000 });
              cell.httpStatus = resp ? resp.status() : null;
              cell.finalUrl = page.url();
              const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
              cell.scrollWidth = scrollWidth;
              cell.overflow = scrollWidth > vp.width + 1;
              cell.consoleErrors = consoleErrors;
            } catch (err) {
              cell.error = String(err);
            } finally {
              page.off("console", onError);
            }
            out.push(cell);
          }
        }
        return { data: out, type: "application/json" };
      }
    JS
  end
end
