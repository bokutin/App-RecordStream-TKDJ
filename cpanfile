requires "Algorithm::Combinatorics" => "0";
requires "Algorithm::Line::Bresenham" => "0";
requires "App::Cmd" => "0";
requires "Color::Similarity" => "0";
requires "Convert::Color" => "0";
requires "IO::All" => "0";
requires "Image::Magick" => "0";
requires "JSON::MaybeXS" => "0";
requires "Lingua::JA::Regular::Unicode" => "0";
requires "List::UtilsBy" => "0";
requires "Modern::Perl" => "0";
requires "Text::Trim" => "0";
requires "XML::Twig" => "0";
requires "rlib" => "0";

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "7.1101";
};
