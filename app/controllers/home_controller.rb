class HomeController < ApplicationController
  def index
    access_token = AmadeusAuthService.new.call
    @flights = access_token ? search_flights(access_token) : []
  end

  def advanced_search; end

  def search_results
    access_token = AmadeusAuthService.new.call
    @flights = access_token ? advanced_search_flights(access_token) : []
    render :search_results
  end

  private

  def advanced_search_flights(access_token)
    search_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    headers = {
      "Authorization" => "Bearer #{access_token}",
      "Content-Type" => "application/json"
    }

    # Default to 30 days from today if no date provided or if date is in the past
    default_date = (Date.today + 30.days).strftime("%Y-%m-%d")
    selected_date = params[:departure_date].presence || default_date

    # Make sure the date is not in the past
    departure_date = Date.parse(selected_date) < Date.today ? default_date : selected_date

    # Format the time to include seconds
    departure_time = "#{params[:departure_time].presence || '10:00'}:00"

    # Build the request payload
    payload = {
      currencyCode: params[:currency].presence || "USD",
      originDestinations: [
        {
          id: "1",
          originLocationCode: params[:origin].presence || "SYD",
          destinationLocationCode: params[:destination].presence || "BKK",
          departureDateTimeRange: {
            date: departure_date,
            time: departure_time
          }
        }
      ],
      travelers: [],
      sources: [ "GDS" ],
      searchCriteria: {
        maxFlightOffers: params[:max_results].presence || 5,
        flightFilters: {
          cabinRestrictions: [
            {
              cabin: params[:cabin_class].presence || "ECONOMY",
              coverage: "MOST_SEGMENTS",
              originDestinationIds: [ "1" ]
            }
          ]
        }
      }
    }

    # Add travelers
    adults = params[:adults].to_i.positive? ? params[:adults].to_i : 1
    children = params[:children].to_i.positive? ? params[:children].to_i : 0
    infants = params[:infants].to_i.positive? ? params[:infants].to_i : 0

    # Add adult travelers
    adults.times do |i|
      payload[:travelers] << {
        id: (i + 1).to_s,
        travelerType: "ADULT"
      }
    end

    # Add child travelers
    children.times do |i|
      payload[:travelers] << {
        id: (adults + i + 1).to_s,
        travelerType: "CHILD"
      }
    end

    # Add infant travelers
    infants.times do |i|
      payload[:travelers] << {
        id: (adults + children + i + 1).to_s,
        travelerType: "INFANT"
      }
    end

    # Add flight filters if needed
    if params[:non_stop].present? && params[:non_stop] == "1"
      payload[:searchCriteria][:flightFilters][:connectionRestriction] = {
        maxNumberOfConnections: 0
      }
    end

    response = HTTP.headers(headers).post(search_url, json: payload)
    process_response(response)
  end
end
