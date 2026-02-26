# frozen_string_literal: true

module Arel
  module FirebirdExtensions
    module SelectManagerExtensions
      attr_reader :parentheses_ignored

      def ignore_parentheses
        @parentheses_ignored = true
        self
      end
    end
  end

  SelectManager.include FirebirdExtensions::SelectManagerExtensions

  module Visitors
    class Firebird < Arel::Visitors::ToSql
      private

      def visit_Arel_Nodes_SelectStatement(o, collector)
        if o.with
          collector = visit o.with, collector
          collector << " "
        end

        collector = o.cores.inject(collector) do |c, x|
          visit_Arel_Nodes_SelectCore(x, c, o)
        end

        unless o.orders.empty?
          collector << " ORDER BY "
          inject_join o.orders, collector, ", "
        end

        collector
      end

      def visit_Arel_Nodes_SelectCore(o, collector, stmt = nil)
        collector << "SELECT"

        collector = collect_optimizer_hints(o, collector)
        collector = maybe_visit o.set_quantifier, collector

        if stmt
          collector = maybe_visit stmt.limit, collector
          collector = maybe_visit stmt.offset, collector
        end

        collector << " "
        collect_nodes_for o.projections, collector, " "

        if o.source && !o.source.empty?
          collector << " FROM "
          collector = visit o.source, collector
        end

        collect_nodes_for o.wheres, collector, " WHERE ", " AND "
        collect_nodes_for o.groups, collector, " GROUP BY "

        unless o.havings.empty?
          collector << " HAVING "
          inject_join o.havings, collector, " AND "
        end

        collect_nodes_for o.windows, collector, " WINDOW "

        collector
      end

      def visit_Arel_Nodes_Limit(o, collector)
        collector << "FIRST "
        visit o.expr, collector
      end

      def visit_Arel_Nodes_Offset(o, collector)
        collector << "SKIP "
        visit o.expr, collector
      end

      def visit_Arel_SelectManager(o, collector)
        return visit(o.ast, collector) if o.parentheses_ignored

        collector << "("
        visit o.ast, collector
        collector << ")"
      end

      def visit_Arel_Nodes_Union(o, collector)
        infix_value o, collector, " UNION "
      end

      def visit_Arel_Nodes_UnionAll(o, collector)
        infix_value o, collector, " UNION ALL "
      end

      def visit_Arel_Nodes_Returning(o, collector)
        collector << " RETURNING "
        inject_join o.expressions, collector, ", "
      end
    end
  end
end
