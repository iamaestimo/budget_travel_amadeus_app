class HomeController < ApplicationController
  def index
    access_token = AmadeusAuthService.new.call
    @flights = access_token ? search_flights(access_token) : []
  end

  private

  def search_flights(access_token)
    search_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    headers = { "Authorization" => "Bearer #{access_token}" }

    # Default to 30 days from today if no date provided or if date is in the past
    default_date = (Date.today + 30.days).strftime("%Y-%m-%d")
    selected_date = params[:departure_date].presence || default_date

    # Make sure the date is not in the past
    departure_date = Date.parse(selected_date) < Date.today ? default_date : selected_date

    query_params = {
      originLocationCode: params[:origin].presence || "SYD",
      destinationLocationCode: params[:destination].presence || "BKK",
      departureDate: departure_date,
      adults: params[:adults].presence || 1
    }

    # Add optional parameters if present
    query_params[:maxPrice] = params[:max_price] if params[:max_price].present?
    query_params[:currencyCode] = params[:currency] if params[:currency].present?

    begin
      response = HTTP.headers(headers).get(search_url, params: query_params)

      if response.status.success?
        process_response(response)
      else
        Rails.logger.error "API Error: #{response.body}"
        @error = "Failed to fetch flights. Please try again later."
        []
      end
    rescue HTTP::Error => e
      Rails.logger.error "HTTP Error: #{e.message}"
      @error = "Connection error occurred. Please try again later."
      []
    rescue StandardError => e
      Rails.logger.error "General Error: #{e.message}"
      @error = "An unexpected error occurred. Please try again later."
      []
    end
  end

  def process_response(response)
    data = JSON.parse(response.body)

    if data["data"]
      data["data"].map do |flight|
        segments = flight.dig("itineraries", 0, "segments") || []

        {
          id: flight["id"],
          price: flight.dig("price", "grandTotal") || "N/A",
          currency: flight.dig("price", "currency") || "USD",
          departure: flight.dig("itineraries", 0, "segments", 0, "departure", "iataCode"),
          arrival: segments.empty? ? nil : segments.last.dig("arrival", "iataCode"),
          departure_time: flight.dig("itineraries", 0, "segments", 0, "departure", "at"),
          arrival_time: segments.empty? ? nil : segments.last.dig("arrival", "at"),
          airline: flight.dig("itineraries", 0, "segments", 0, "carrierCode"),
          flight_number: flight.dig("itineraries", 0, "segments", 0, "number"),
          duration: flight.dig("itineraries", 0, "duration"),
          stops: segments.length - 1,
          cabin_class: flight.dig("travelerPricings", 0, "fareDetailsBySegment", 0, "cabin"),
          aircraft: flight.dig("itineraries", 0, "segments", 0, "aircraft", "code"),
          segments: segments.map do |segment|
            {
              departure_airport: segment.dig("departure", "iataCode"),
              departure_terminal: segment.dig("departure", "terminal"),
              departure_time: segment.dig("departure", "at"),
              arrival_airport: segment.dig("arrival", "iataCode"),
              arrival_terminal: segment.dig("arrival", "terminal"),
              arrival_time: segment.dig("arrival", "at"),
              carrier: segment.dig("carrierCode"),
              flight_number: segment.dig("number"),
              aircraft: segment.dig("aircraft", "code"),
              duration: segment.dig("duration")
            }
          end
        }
      end
    else
      if data["errors"]
        Rails.logger.error "API Error: #{data['errors']}"
        @error = data["errors"].first&.dig("detail") || "An error occurred while fetching flights."
      else
        Rails.logger.error "Unknown API Error: #{data}"
        @error = "Unknown error occurred while fetching flights."
      end
      []
    end
  rescue => e
    Rails.logger.error "Flight Search Error: #{e.message}"
    @error = "Error: #{e.message}"
    []
  end
end
