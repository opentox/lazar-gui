post "/aa/authenticate/?" do
  mime_types = ["text/plain"]
  bad_request_error "Mime type #{@accept} not supported here. Please request data as  #{mime_types.join(', ')}." unless mime_types.include? @accept
  bad_request_error "Please send formdata username." unless params[:username]
  bad_request_error "Please send formdata password." unless params[:password]
  case @accept
  when "text/plain"
    if OpenTox::Authorization.authenticate(params[:username], params[:password])
      return OpenTox::RestClientWrapper.subjectid
    else
      return nil
    end
  else
    bad_request_error "'#{@accept}' is not a supported content type."
   end
end

post "/aa/logout/?" do
  mime_types = ["text/plain"]
  bad_request_error "Mime type #{@accept} not supported here. Please request data as  #{mime_types.join(', ')}." unless mime_types.include? @accept
  bad_request_error "Please send formdata subjectid." unless params[:subjectid]
  case @accept
  when "text/plain"
    if OpenTox::Authorization.logout(params[:subjectid])
      return "Successfully logged out. \n"
    else
      return "Logout failed.\n"
    end
  else
    bad_request_error "'#{@accept}' is not a supported content type."
   end
end

module OpenTox

  AA = "https://opensso.in-silico.ch"
  
  module Authorization
    #Authentication against OpenSSO. Returns token. Requires Username and Password.
    # @param user [String] Username
    # @param pw [String] Password
    # @return [Boolean] true if successful
    def self.authenticate(user, pw)
      begin
        res = RestClientWrapper.post("#{AA}/auth/authenticate",{:username=>user, :password => pw},{:subjectid => ""}).sub("token.id=","").sub("\n","")
        if is_token_valid(res)
          RestClientWrapper.subjectid = res
          return true
        else
          bad_request_error "Authentication failed #{res.inspect}"
        end
      rescue
        bad_request_error "Authentication failed #{res.inspect}"
      end
    end

    #Logout on opensso. Make token invalid. Requires token
    # @param [String] subjectid the subjectid
    # @return [Boolean] true if logout is OK
    def self.logout(subjectid=RestClientWrapper.subjectid)
      begin
        out = RestClientWrapper.post("#{AA}/auth/logout", :subjectid => subjectid)
        return true unless is_token_valid(subjectid)
      rescue
        return false
      end
      return false
    end

    #Checks if a token is a valid token
    # @param [String]subjectid subjectid from openSSO session
    # @return [Boolean] subjectid is valid or not.
    def self.is_token_valid(subjectid=RestClientWrapper.subjectid)
      begin
        return true if RestClientWrapper.post("#{AA}/auth/isTokenValid",:tokenid => subjectid) == "boolean=true\n"
      rescue #do rescue because openSSO throws 401
        return false
      end
      return false
    end
  end
end