#include <Parsers/ASTProjectionDeclaration.h>
#include <Common/quoteString.h>


namespace DB
{
ASTPtr ASTProjectionDeclaration::clone() const
{
    auto clone = std::make_shared<ASTProjectionDeclaration>(*this);
    clone->cloneChildren();
    return clone;
}


void ASTProjectionDeclaration::formatImpl(const FormatSettings & settings, FormatState & state, FormatStateStacked frame) const
{
    settings.ostr << backQuoteIfNeed(name);
    std::string indent_str = settings.one_line ? "" : std::string(4u * frame.indent, ' ');
    std::string nl_or_nothing = settings.one_line ? "" : "\n";
    settings.ostr << nl_or_nothing << indent_str << "(" << nl_or_nothing;
    FormatStateStacked frame_nested = frame;
    frame_nested.need_parens = false;
    ++frame_nested.indent;
    query->formatImpl(settings, state, frame_nested);
    settings.ostr << nl_or_nothing << indent_str << ")";
    settings.ostr << (settings.hilite ? hilite_keyword : "") << " TYPE " << (settings.hilite ? hilite_none : "") << type;
}

}
