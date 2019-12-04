class UsersController < ApplicationController
  before_action :jwt_init
  before_action :jwt_required, only: %i[show
                                        show_many
                                        edit_emailcheck
                                        edit_emailcheck_complete
                                        update]

  def show
    # return render status: 400 unless params[:userId]
    #
    # user = User.find_by_id(params[:userId])
    # return render status: 404 unless user
    # TO BE CONTINUED
  end

  def show_many
    return render status: 400 unless params[:name]

    user_list = Hash.new
    cnt = 1
    User.where('name LIKE ?', "%#{params[:name]}%").each do |user|
      user_list[cnt] = { user_id: user.id, name: user.name }
      cnt += 1
    end

    render status: 404 if user_list.blank?
    render json: user_list, status: 200
  end

  def create
    return render status: 400 if params[:email].blank? || params[:name].blank?
    return render status: 409 if User.find_by_email(params[:email])

    auth_code = create_auth_code
    overlap = TempUser.find_by_email(params[:email])

    if overlap
      overlap.name = params[:name]
      overlap.auth_code = auth_code
      overlap.save
    else
      TempUser.create!(email: params[:email],
                       name: params[:name],
                       auth_code: auth_code)
    end

    AuthMailer.send_auth_code(params[:email],
                              auth_code).deliver_later
    render status: 204
  end

  def emailcheck_get
    return render status: 400 if params[:email].blank?

    if User.find_by_email(params[:email])
      render status: 204
    else
      render status: 409
    end
  end

  def emailcheck_post
    return render status: 400 if params[:authCode].blank?

    temp_user = TempUser.find_by_auth_code(params[:authCode])

    if temp_user.created_at.to_i + 10.minutes.to_i < Time.now.to_i
      return render status: 408
    end

    if temp_user
      temp_user.verified = true
      temp_user.save
      render json: { tempUserId: temp_user.id }, status: 200
    else
      render status: 403
    end
  end

  def create_complete
    if params[:tempUserId].blank? || params[:password].blank?
      return render status: 400
    end

    temp_user = TempUser.find_by_id(params[:tempUserId])
    return render status: 404 if temp_user.nil?

    if temp_user.verified
      User.create!(name: temp_user.name,
                   email: temp_user.email,
                   password: params[:password],
                   profile_img: '')
      temp_user.destroy
      render status: 201
    else
      render status: 403
    end
  end

  def edit_emailcheck
    payload = @@jwt_extended.get_jwt_payload(request.authorization[7..])
    auth_code = create_auth_code
    AuthMailer.send_auth_code(User.find_by_id(payload['user_id']).email,
                              auth_code).deliver_later
    render json: { access_code: @@jwt_extended.create_access_token(payload['auth_code'] += auth_code) },
           status: 200
  end

  def edit_emailcheck_complete
    return render status: 400 if params[:authCode].blank?
    return render status: 412 unless params[:authCode] == payload['auth_code']

    payload = @@jwt_extended.get_jwt_payload(request.authorization[7..])

    user = User.find_by_id(payload['user_id'])

    if user.created_at.to_i + 10.minutes.to_i < Time.now.to_i
      return render status: 408
    end

    payload = @@jwt_extended.get_jwt_payload(request.authorization[7..])
    user = User.find_by_id(payload['user_id'])
    user.verified = true
    user.save

    render status: 200
  end

  def update
    unless params[:newName].blank? || params[:newPassword].blank?
      return render status: 400
    end

    payload = @@jwt_extended.get_jwt_payload(request.authorization[7..])
    user = User.find_by_id(payload['user_id'])

    if params[:newName]
      user.name = params[:newName]
      user.save
    end

    if params[:newPassword]
      return render status: 428 unless user.verified

      user.password = params[:newPassword]
      user.verified = false
      user.save
    end

    render status: 200
  end
end