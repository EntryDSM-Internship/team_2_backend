class UsersController < ApplicationController
  before_action :jwt_init
  before_action :jwt_required, only: %i[
                                        show_many
                                        edit_emailcheck
                                        edit_emailcheck_complete
                                        update]

  def show
    return render status: 400 unless params[:page]

    user = User.find_by_id(params[:userId])
    return render status: 404 unless user

    render json: { name: user.name,
                   email: user.email,
                   user_profile: user.user_imgs.last,
                   following: Follow.where(following_id: params[:userId],
                                           accepted: true).count - 1,
                   follower: Follow.where(follower_id: params[:userId],
                                          accepted: true).count - 1,
                   tweets: user.tweets.order(created_at: :desc).limit(10)
                               .offset(10 * params[:page].to_i).ids },
           status: 200
  end

  def show_many
    return render status: 400 unless params[:name]

    payload = @@jwt_extended.get_jwt_payload(request.authorization)

    user_list = User.where('name LIKE ?', "%#{params[:name]}%").ids

    if user_list.include?(payload['user_id'])
      user_list.delete(payload['user_id'])
    end

    render status: 404 unless user_list
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
    return render status: 400 unless params[:email]

    if User.find_by_email(params[:email]).blank?
      render status: 204
    else
      render status: 409
    end
  end

  def emailcheck_post
    return render status: 400 unless params[:authCode]

    temp_user = TempUser.find_by_auth_code(params[:authCode])

    if temp_user.updated_at.to_i + 10.minutes.to_i < Time.now.to_i
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
    return render status: 404 unless temp_user

    if temp_user.verified
      User.create!(name: temp_user.name,
                   email: temp_user.email,
                   password: params[:password])
      temp_user.destroy

      Follow.create!(follower_id: User.last.id,
                     following_id: User.last.id,
                     accepted: true)

      User.last.user_imgs.create!(source: File.open('public/uploads/tmp/default.jpg', 'r'))

      render status: 201
    else
      render status: 403
    end
  end
  def edit_emailcheck
    payload = @@jwt_extended.get_jwt_payload(request.authorization)
    auth_code = create_auth_code
    user = User.find_by_id(payload['user_id'])
    AuthMailer.send_auth_code(user.email,
                              auth_code).deliver_later
    user.sended_at = Time.now
    user.save
    payload['auth_code'] = auth_code
    render json: { access_code: @@jwt_extended.create_access_token(payload) },
           status: 200
  end

  def edit_emailcheck_complete
    return render status: 400 unless params[:authCode]
    return render status: 412 unless params[:authCode] == payload['auth_code']

    payload = @@jwt_extended.get_jwt_payload(request.authorization)

    user = User.find_by_id(payload['user_id'])

    if user.sended_at.to_i + 10.minutes.to_i < Time.now.to_i
      return render status: 408
    end

    user.verified = true
    user.save

    render status: 200
  end

  def update
    if params[:newName].blank? && params[:newPassword].blank? && params[:newProfileImg].blank?
      return render status: 400
    end

    payload = @@jwt_extended.get_jwt_payload(request.authorization)
    user = User.find_by_id(payload['user_id'])
    user.name = params[:newName] if params[:newName]

    if params[:newPassword]
      return render status: 428 unless user.verified

      user.password = params[:newPassword]
      user.verified = false
    end

    user.save

    if params[:newProfileImg]
      user.user_imgs.create!(source: params[:newProfileImg])
    end

    render status: 200
  end
end
