post "/api/authenticate/login/?" do
  halt 400, "Please send formdata username." unless params[:username]
  halt 400, "Please send formdata password." unless params[:password]
  if OpenTox::Authorization.authenticate(params[:username], params[:password], params[:onetimetoken])
    return {"subjectid": "#{OpenTox::RestClientWrapper.subjectid}"}.to_json
  else
    unauthorized_error "Unable to register user."
  end
end

post "/api/authenticate/logout/?" do
  halt 400, "Please send formdata subjectid." unless params[:subjectid]
  halt 400, "Invalid subjectid." unless OpenTox::Authorization.is_token_valid(params[:subjectid])
  if OpenTox::Authorization.logout
    return "Successfully logged out. \n".to_json
  else
    unauthorized_error "Logout failed."
  end
end

module OpenTox

  AA = "https://sso.prod.openrisknet.org/auth/realms/openrisknet/protocol/openid-connect"
  CLIENT_ID = "lazar-api"
  CLIENT_SECRET = "d1163ef6-fbb2-4c2b-a1df-8d250673f98e"
  
  module Authorization
    #Authentication against OpenSSO. Returns token. Requires Username and Password.
    # @param user [String] Username
    # @param pw [String] Password
    # @return [Boolean] true if successful
    def self.authenticate(user, pw, totp=nil)
      begin
        request = RestClientWrapper.post("#{AA}/token",{:client_id => CLIENT_ID, :client_secret => CLIENT_SECRET, :grant_type =>"password", :username => user, :password => pw, :totp => totp})
	      res = JSON.parse(request.body)
	      token = res["access_token"]
	      if is_token_valid(token)
          RestClientWrapper.subjectid = token
          RestClientWrapper.refresh = res["refresh_token"]
          return true
        else
          halt 400, "Authentication failed #{res.inspect}"
        end
      rescue
        halt 400, "Authentication failed #{res.inspect}"
      end
    end

    #Logout on opensso. Make token invalid. Requires token
    # @param [String] subjectid the subjectid
    # @return [Boolean] true if logout is OK
    def self.logout(refresh=RestClientWrapper.refresh)
      begin
        out = RestClientWrapper.post("#{AA}/logout", {:client_id => CLIENT_ID, :client_secret => CLIENT_SECRET, :refresh_token => refresh})
        if out.code == 204
          RestClientWrapper.subjectid = nil
          RestClientWrapper.refresh = nil
          return true
        end
      rescue
        return false
      end
      return false
    end

    #Checks if a token is a valid token
    # @param [String]subjectid subjectid from openSSO session
    # @return [Boolean] subjectid is valid or not.
    #def self.is_token_valid(subjectid=RestClientWrapper.subjectid)
    def self.is_token_valid(subjectid)
      begin
        r = RestClientWrapper.post("#{AA}/token/introspect", {:client_id => CLIENT_ID, :client_secret => CLIENT_SECRET, :token => subjectid})
        res = JSON.parse(r.body)
        return res["active"].to_s.to_boolean
      rescue
        return false
      end
      return false
    end
  end
end
