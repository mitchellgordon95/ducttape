package ducttape.syntax
//import scala.util.parsing.combinator.Parsers.ParseResult
import ducttape.syntax.AbstractSyntaxTree._
import ducttape.syntax.Grammar._
import ducttape.syntax.GrammarParser._
  
object DemoParser extends Application {

  {
    val result: ParseResult[Tape] = parseAll(tape,"""[hello]""")   
    println(result.get)
  }
  
  {
    val result: ParseResult[String] = parseAll(Grammar.quotedLiteral,"""'hi\tthere\nc:\\world'""")   
    println(result.get)    
  }
}