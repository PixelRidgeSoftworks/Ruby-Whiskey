# Whiskey::ORM

A modular Object-Relational Mapping system using the "Whiskey Glass" metaphor. Objects can be "filled" with data and "drunk" (persisted to the database).

## Features

- **Modular Design**: Enable only the features you need
- **Whiskey Glass Metaphor**: Intuitive API using `fill`, `drink`, and glass state management
- **Optional Modules**:
  - **Validations**: Declarative validations (presence, uniqueness, length, format)
  - **Associations**: Relationships between models (has_one, has_many, belongs_to)
  - **Query**: Chainable query DSL for filtering, ordering, and limits
  - **Serialization**: Convert objects to JSON, XML, YAML
  - **Callbacks**: Lifecycle hooks (before_fill, after_drink, around_drink)
  - **Persistence**: Pluggable database adapters

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'whiskey-orm'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install whiskey-orm

## Quick Start

### Basic Usage

```ruby
require 'whiskey/orm'

# Basic Glass class
class User < Whiskey::ORM::Core::Model
  table :users
end

# Create and fill a glass
user = User.new
user.fill(name: "John Doe", email: "john@example.com")

# Check glass state
user.filled?  # => true
user.drunk?   # => false

# Drink (persist) the glass
user.drink    # => true (basic persistence)
user.drunk?   # => true
```

### Enabling Optional Modules

```ruby
# Enable specific modules
Whiskey::ORM.enable(:validations)
Whiskey::ORM.enable(:persistence)
Whiskey::ORM.enable(:associations)

# Or configure with a block
Whiskey::ORM.configure do |config|
  config[:validations] = true
  config[:persistence] = true
  config[:query] = true
end
```

### Validations

```ruby
require 'whiskey/orm'
Whiskey::ORM.enable(:validations)

class User < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Validations
  
  validates_presence_of :name, :email
  validates_format_of :email, with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  validates_length_of :name, minimum: 2, maximum: 50
end

user = User.new
user.fill(name: "", email: "invalid")
user.valid?  # => false
user.errors_for(:name)   # => ["can't be blank"]
user.errors_for(:email)  # => ["has invalid format"]
```

### Associations

```ruby
require 'whiskey/orm'
Whiskey::ORM.enable(:associations)

class User < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Associations
  
  has_many :posts
  has_one :profile
end

class Post < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Associations
  
  belongs_to :user
end

user = User.new(name: "John")
user.posts = [Post.new(title: "Hello World")]
```

### Query DSL

```ruby
require 'whiskey/orm'
Whiskey::ORM.enable(:query)

class User < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Query
end

# Chainable queries
users = User.where(active: true)
            .order(:name, :asc)
            .limit(10)
            .offset(20)

# Find methods
user = User.find(1)
user = User.find_by(email: "john@example.com")
users = User.all
count = User.count
```

### Serialization

```ruby
require 'whiskey/orm'
Whiskey::ORM.enable(:serialization)

class User < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Serialization
  
  serialize_with include: [:name, :email], exclude: [:password_hash]
end

user = User.new(name: "John", email: "john@example.com")

# Serialize to different formats
user.to_json          # => JSON string
user.to_pretty_json   # => Pretty formatted JSON
user.to_yaml          # => YAML string
user.to_xml           # => XML string
user.to_hash          # => Hash

# Parse from formats
User.from_json('{"name":"John","email":"john@example.com"}')
```

### Callbacks

```ruby
require 'whiskey/orm'
Whiskey::ORM.enable(:callbacks)

class User < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Callbacks
  
  before_fill :normalize_email
  after_drink :send_welcome_email
  around_drink :log_persistence
  
  private
  
  def normalize_email
    self[:email] = self[:email]&.downcase&.strip
  end
  
  def send_welcome_email
    # Send email logic
  end
  
  def log_persistence(block)
    puts "Starting persistence..."
    result = block.call
    puts "Persistence completed: #{result}"
    result
  end
end
```

### Persistence

```ruby
require 'whiskey/orm'
Whiskey::ORM.enable(:persistence)

class User < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Persistence
  
  persistence_adapter :memory  # Use in-memory adapter
end

# Create and persist
user = User.create(name: "John", email: "john@example.com")

# Find and update
user = User.find(1)
user.fill(name: "Jane")
user.drink  # Persist changes

# Delete
user.destroy
```

## Core Concepts

### Glass States

Every Glass object can be in one of three states:

1. **Empty**: No data filled (`filled? => false`, `drunk? => false`)
2. **Filled**: Data present but not persisted (`filled? => true`, `drunk? => false`)
3. **Drunk**: Data persisted (`filled? => true`, `drunk? => true`)

### Glass Methods

- `fill(data)`: Fill the glass with data
- `drink`: Persist the glass (returns true/false)
- `empty!`: Clear all data and reset state
- `filled?`: Check if glass has data
- `drunk?`: Check if glass has been persisted

### Modular Architecture

Whiskey::ORM is designed to be modular. You only load what you need:

```ruby
# Check what's enabled
Whiskey::ORM.enabled?(:validations)  # => true/false

# Enable modules as needed
Whiskey::ORM.enable(:validations)
Whiskey::ORM.enable(:associations)
```

## Persistence Adapters

### Built-in Adapters

- **Memory Adapter**: In-memory storage for testing/development

### Custom Adapters

Create custom adapters by inheriting from `Whiskey::ORM::Persistence::BaseAdapter`:

```ruby
class SQLiteAdapter < Whiskey::ORM::Persistence::BaseAdapter
  def connect
    # Connect to SQLite database
  end
  
  def insert(table_name, attributes)
    # Insert record and return attributes with id
  end
  
  # Implement other required methods...
end

# Register the adapter
Whiskey::ORM::Persistence::AdapterRegistry.register(:sqlite, SQLiteAdapter)

# Use the adapter
class User < Whiskey::ORM::Core::Model
  include Whiskey::ORM::Persistence
  
  persistence_adapter :sqlite, database: "app.db"
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/PixelRidgeSoftworks/Ruby-Whiskey.

## License

The gem is available as open source under the terms of the [AGPL-3.0 License](https://opensource.org/licenses/AGPL-3.0).
