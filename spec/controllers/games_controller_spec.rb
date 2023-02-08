# (c) goodprogrammer.ru

require 'rails_helper'
require 'support/my_spec_helper' # наш собственный класс с вспомогательными методами

# Тестовый сценарий для игрового контроллера
# Самые важные здесь тесты:
#   1. на авторизацию (чтобы к чужим юзерам не утекли не их данные)
#   2. на четкое выполнение самых важных сценариев (требований) приложения
#   3. на передачу граничных/неправильных данных в попытке сломать контроллер
#
RSpec.describe GamesController, type: :controller do
  let(:user) { FactoryGirl.create(:user) }
  let(:admin) { FactoryGirl.create(:user, is_admin: true) }
  let(:game_w_questions) { FactoryGirl.create(:game_with_questions, user: user) }
  let(:game) { assigns(:game) } # вытаскиваем из контроллера поле @game

  describe '#show' do
    context 'anonymous user' do
      before { get :show, id: game_w_questions.id }

      it 'kick from #show' do
        expect(response.status).not_to eq(200) # статус не 200 ОК
        expect(response).to redirect_to(new_user_session_path) # devise должен отправить на логин
        expect(flash[:alert]).to be # во flash должен быть прописана ошибка
      end
    end

    context 'signed in user'do
      before do
        sign_in user
        get :show, id: game_w_questions.id
      end

      it 'returns games#show' do
        expect(game.finished?).to be false
        expect(game.user).to eq(user)
        expect(response.status).to eq(200) # должен быть ответ HTTP 200
        expect(response).to render_template('show') # и отрендерить шаблон show
      end

      context 'trying to watch strange games#show' do
        let(:strange_game) { FactoryGirl.create(:game_with_questions) }
        # пользователь не может смотреть чужую игру
        it 'cannot watch strange games#show' do
          # пробуем зайти на эту игру
          get :show, id: strange_game.id
          expect(response.status).not_to eq(200)
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to be
        end
      end
    end
  end

  describe '#create' do
    context 'anonymous user' do
      before { post :create, id: game_w_questions.id }

      it 'kick from #create' do
        expect(response.status).not_to eq(200)
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to be
      end
    end

    context 'signed in user'do
      before { sign_in user }

      context 'creates first game' do
        before do
          generate_questions(15)
          post :create
        end

        it 'creates game' do
          expect(game.finished?).to be false
          expect(game.user).to eq(user)
          expect(response).to redirect_to(game_path(game))
          expect(flash[:notice]).to be
        end
      end

      context 'trying to create second game' do
        # пользователь не может начать вторую игру, не закончив первой
        before do
          expect(game_w_questions.finished?).to be false
          expect { post :create}.to change(Game, :count).by(0)
        end

        it 'cannot create second game' do
          expect(game).to be_nil
          expect(response).to redirect_to(game_path(game_w_questions))
          expect(flash[:alert]).to be
        end
      end
    end
  end

  describe '#answer' do
    context 'anonymous user' do
      before { put :answer, id: game_w_questions.id, letter: game_w_questions.current_game_question.correct_answer_key }

      it 'kick from #answer' do
        expect(response.status).not_to eq(200)
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to be
      end
    end

    context 'signed in user'do
      before do
        sign_in user
        put :answer, id: game_w_questions.id, letter: game_w_questions.current_game_question.correct_answer_key
      end

      it 'answers correct' do
        expect(game.finished?).to be false
        expect(game.current_level).to be > 0
        expect(response).to redirect_to(game_path(game))
        expect(flash.empty?).to be_truthy # удачный ответ не заполняет flash
      end
    end
  end

  describe '#take_money' do
    context 'anonymous user' do
      before { put :take_money, id: game_w_questions.id }

      it 'kick from #take_money' do
        expect(response.status).not_to eq(200)
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to be
      end
    end

    context 'signed in user'do
      before do
        sign_in user
        game_w_questions.update_attribute(:current_level, 2)
        put :take_money, id: game_w_questions.id
      end

      # пользователь берет деньги до конца игры
      it 'takes money' do
        expect(game.finished?).to be true
        expect(game.prize).to eq(200)
      end

      it 'reloads user' do
        user.reload
        expect(user.balance).to eq(200)
      end

      it 'redirects to user profile' do
        expect(response).to redirect_to(user_path(user))
        expect(flash[:warning]).to be
      end
    end
  end

  describe '#help' do
    context 'anonymous user' do
      before { put :help, id: game_w_questions.id, help_type: :audience_help }

      it 'kick from #help' do
        expect(response.status).not_to eq(200)
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to be
      end
    end

    context 'signed in user'do
      before do
        sign_in user
        # сперва проверяем что в подсказках текущего вопроса пусто
        expect(game_w_questions.current_game_question.help_hash[:audience_help]).not_to be
        expect(game_w_questions.audience_help_used).to be false

        put :help, id: game_w_questions.id, help_type: :audience_help
      end

      it 'uses audience help' do
        # проверяем, что игра не закончилась, что флажок установился, и подсказка записалась
        expect(game.finished?).to be false
        expect(game.audience_help_used).to be true
        expect(game.current_game_question.help_hash[:audience_help]).to be
        expect(game.current_game_question.help_hash[:audience_help].keys).to contain_exactly('a', 'b', 'c', 'd')
        expect(response).to redirect_to(game_path(game))
      end
    end
  end
end
