//! Protocol Buffer parser error types and utilities.
//! This module defines all possible errors that can occur during parsing
//! of Protocol Buffer definition files (.proto), organized by category.

//               .'\   /`.
//             .'.-.`-'.-.`.
//        ..._:   .-. .-.   :_...
//      .'    '-.(o ) (o ).-'    `.
//     :  _    _ _`~(_)~`_ _    _  :
//    :  /:   ' .-=_   _=-. `   ;\  :
//    :   :|-.._  '     `  _..-|:   :
//     :   `:| |`:-:-.-:-:'| |:'   :
//      `.   `.| | | | | | |.'   .'
//        `.   `-:_| | |_:-'   .'
//          `-._   ````    _.-'
//              ``-------''
//
// Created by ab, 12.06.2024

/// Comprehensive set of errors that can occur during Protocol Buffer parsing.
/// Errors are grouped by category for better organization and documentation.
pub const Error = error{
    //=== Syntax and Structure Errors ===//

    /// Invalid proto syntax definition (e.g., missing 'syntax' statement)
    InvalidSyntaxDef,
    /// Reached end of file unexpectedly while parsing
    UnexpectedEOF,
    /// Expected whitespace but found none
    SpaceRequired,
    /// Invalid or unsupported syntax version specified
    InvalidSyntaxVersion,
    /// Unexpected token encountered during parsing
    UnexpectedToken,
    /// Package has already been defined in this file
    PackageAlreadyDefined,
    /// Edition has already been defined in this file
    EditionAlreadyDefined,

    //=== String Parsing Errors ===//

    /// Invalid string literal format
    InvalidStringLiteral,
    /// Invalid Unicode escape sequence in string
    InvalidUnicodeEscape,
    /// Invalid escape sequence in string
    InvalidEscape,

    //=== Syntax Element Errors ===//

    /// Missing expected semicolon
    SemicolonExpected,
    /// Missing expected assignment operator
    AssignmentExpected,
    /// Missing expected bracket
    BracketExpected,

    //=== Identifier and Name Errors ===//

    /// Identifier must start with a letter
    IdentifierShouldStartWithLetter,
    /// Invalid option name format
    InvalidOptionName,
    /// Invalid field name format
    InvalidFieldName,

    //=== Value and Type Errors ===//

    /// Option declaration missing required value
    OptionValueRequired,
    /// Invalid integer literal format
    InvalidIntegerLiteral,
    /// Invalid boolean literal format
    InvalidBooleanLiteral,
    /// Invalid constant value
    InvalidConst,
    /// Invalid floating point number format
    InvalidFloat,
    /// Invalid field value
    InvalidFieldValue,
    /// Invalid map key type specified
    InvalidMapKeyType,
    /// Invalid map value type specified
    InvalidMapValueType,

    //=== Definition Errors ===//

    /// Invalid enum definition
    InvalidEnumDef,
    /// Invalid oneof element
    InvalidOneOfElement,
    /// Invalid extensions range specification
    InvalidExtensionsRange,

    //=== Reference and Resolution Errors ===//

    /// Referenced extend source type not found
    ExtendSourceNotFound,
    /// Referenced type not found
    TypeNotFound,

    //=== System and Runtime Errors ===//

    /// Numeric overflow occurred during parsing
    Overflow,
    /// Invalid character encountered
    InvalidCharacter,
    /// Memory allocation failed
    OutOfMemory,

    //=== Feature Support ===//

    /// Attempted to use an unsupported protocol buffer feature
    FeatureNotSupported,
};
