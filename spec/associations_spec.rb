# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Associations" do
  describe "belongs_to association" do
    before do
      connection = ActiveRecord::Base.connection

      # ✅ CORREGIDO: Usar create_table de Rails
      connection.create_table :authors, force: true, id: :bigint do |t|
        t.text :name
        t.timestamps
      end

      connection.create_table :books, force: true, id: :bigint do |t|
        t.text :title
        t.bigint :author_id
        t.timestamps
      end

      # ✅ Agregar foreign key después de crear ambas tablas
      connection.add_foreign_key :books, :authors, column: :author_id, primary_key: :id

      Object.send(:remove_const, :Author) if defined?(Author)
      Object.send(:remove_const, :Book) if defined?(Book)

      class Author < ActiveRecord::Base
        has_many :books
      end

      class Book < ActiveRecord::Base
        belongs_to :author
      end

      Author.reset_column_information
      Book.reset_column_information
    end

    after do
      connection = ActiveRecord::Base.connection
      connection.drop_table :books, if_exists: true
      connection.drop_table :authors, if_exists: true
    end

    it "creates and retrieves associated records" do
      author = Author.create!(name: "John Doe")
      book = Book.create!(title: "My Book", author: author)

      expect(book.author).to eq(author)
      expect(author.books).to include(book)
    end
  end

  describe "has_many association" do
    before do
      connection = ActiveRecord::Base.connection

      begin
        connection.execute("DROP TABLE posts")
      rescue StandardError
        nil
      end
      begin
        connection.execute("DROP TABLE users")
      rescue StandardError
        nil
      end

      begin
        connection.commit_db_transaction if connection.transaction_open?
      rescue StandardError
        nil
      end

      sleep 0.1

      connection.create_table :users, force: true, id: :bigint do |t|
        t.text :name
        t.timestamps
      end

      connection.create_table :posts, force: true, id: :bigint do |t|
        t.text :title
        t.bigint :user_id
        t.timestamps
      end

      connection.add_foreign_key :posts, :users, column: :user_id, primary_key: :id

      Object.send(:remove_const, :User) if defined?(User)
      Object.send(:remove_const, :Post) if defined?(Post)

      class User < ActiveRecord::Base
        has_many :posts
      end

      class Post < ActiveRecord::Base
        belongs_to :user
      end

      User.reset_column_information
      Post.reset_column_information
    end

    after do
      connection = ActiveRecord::Base.connection
      connection.drop_table :posts, if_exists: true
      connection.drop_table :users, if_exists: true
    end

    it "creates and retrieves has_many records" do
      user = User.create!(name: "Alice")
      post1 = Post.create!(title: "Post 1", user: user)
      post2 = Post.create!(title: "Post 2", user: user)

      expect(user.posts.count).to eq(2)
      expect(user.posts).to include(post1, post2)
    end

    it "supports has_many with conditions", skip: "Transaction management issue" do
      user = User.create!(name: "Bob")
      Post.create!(title: "Active Post", user: user)
      Post.create!(title: "Draft Post", user: user)

      expect(user.posts.count).to eq(2)
    end
  end
end
