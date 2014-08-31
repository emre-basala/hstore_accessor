require "byebug"
module HstoreAccessor
  module Macro
    module ClassMethods

      def hstore_accessor(hstore_attribute, fields)
        define_method("hstore_metadata_for_#{hstore_attribute}") do
          fields
        end

        field_methods = Module.new

        @@a = []
        fields.each do |key, type|
          data_type = type
          store_key = key

          if type.is_a?(Hash)
            type = type.with_indifferent_access
            data_type   = type[:data_type]
            store_key   = type[:store_key]
            default     = type[:default]
            if default.present?
              @@a << (->(s) { s.send("#{key}=", default) unless s.send("#{key}") })
            end
          end

          data_type = data_type.to_sym

          raise Serialization::InvalidDataTypeError unless Serialization::VALID_TYPES.include?(data_type)

          field_methods.send(:define_method, "#{key}=") do |value|
            casted_value = TypeHelpers.cast(data_type, value)
            serialized_value = serialize(data_type, casted_value)

            unless send(key) == casted_value
              send(:attribute_will_change!, key)
              send("#{hstore_attribute}_will_change!")
            end

            send("#{hstore_attribute}=", (send(hstore_attribute) || {}).merge(store_key.to_s => serialized_value))
          end

          field_methods.send(:define_method, key) do
            value = send(hstore_attribute) && send(hstore_attribute).with_indifferent_access[store_key.to_s]
            deserialize(data_type, value)
          end

          field_methods.send(:define_method, "#{key}?") do
            send("#{key}").present?
          end

          field_methods.send(:define_method, "#{key}_changed?") do
            send(:attribute_changed?, key)
          end

          field_methods.send(:define_method, "#{key}_was") do
            send(:attribute_was, key)
          end

          field_methods.send(:define_method, "#{key}_change") do
            send(:attribute_change, key)
          end

          query_field = "#{hstore_attribute} -> '#{store_key}'"

          case data_type
          when :string
            send(:scope, "with_#{key}", -> value { where("#{query_field} = ?", value.to_s) })
          when :integer, :float, :decimal
            send(:scope, "#{key}_lt", -> value { where("(#{query_field})::#{data_type} < ?", value.to_s) })
            send(:scope, "#{key}_lte", -> value { where("(#{query_field})::#{data_type} <= ?", value.to_s) })
            send(:scope, "#{key}_eq", -> value { where("(#{query_field})::#{data_type} = ?", value.to_s) })
            send(:scope, "#{key}_gte", -> value { where("(#{query_field})::#{data_type} >= ?", value.to_s) })
            send(:scope, "#{key}_gt", -> value { where("(#{query_field})::#{data_type} > ?", value.to_s) })
          when :time
            send(:scope, "#{key}_before", -> value { where("(#{query_field})::integer < ?", value.to_i) })
            send(:scope, "#{key}_eq", -> value { where("(#{query_field})::integer = ?", value.to_i) })
            send(:scope, "#{key}_after", -> value { where("(#{query_field})::integer > ?", value.to_i) })
          when :date
            send(:scope, "#{key}_before", -> value { where("#{query_field} < ?", value.to_s) })
            send(:scope, "#{key}_eq", -> value { where("#{query_field} = ?", value.to_s) })
            send(:scope, "#{key}_after", -> value { where("#{query_field} > ?", value.to_s) })
          when :boolean
            send(:scope, "is_#{key}", -> { where("#{query_field} = 'true'") })
            send(:scope, "not_#{key}", -> { where("#{query_field} = 'false'") })
          when :array
            send(:scope, "#{key}_eq", -> value { where("#{query_field} = ?", value.join(Serialization::SEPARATOR)) })
            send(:scope, "#{key}_contains", -> value { where("string_to_array(#{query_field}, '#{Serialization::SEPARATOR}') @> string_to_array(?, '#{Serialization::SEPARATOR}')", Array[value].flatten.join(Serialization::SEPARATOR)) })
          end
        end

        field_methods.send(:define_method, "callbacks") do
         return @@a
        end

        include field_methods
      end
    end

  end

  def self.included(base)
    base.send(:after_initialize, -> { callbacks.each { |callback| callback.call(self) } } )
  end

end
