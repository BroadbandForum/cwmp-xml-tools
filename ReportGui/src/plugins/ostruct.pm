# klaus.wich@nsn.com
# Display structure as text
package ostruct;

$gInd = 1;
$gIndTab = 4;


@ids = (0,0,0,0,0,0,0,0,0,0,0,0,0);
$MAXID = 12;

my %DataTypesTable;

sub indprint
{
	printf("% ${_[0]}s%s\n", "",$_[1]);
}


sub resetid
{
	my ($lev) = @_;
	for ($i= $lev+1; $i < $MAXID; $i++)
	{
		@ids[$i] = 0;
	}
}


sub ostruct_node
{
	my ($node, $ind) = @_;
	if ($ind == 0)
	{
		foreach my $dtype (@{$node->{dataTypes}})
		{
			$type = ($dtype->{base} ne "") ? $dtype->{base} : $dtype->{prim};
			$tsize = 0;
			$syn = $dtype->{syntax};
			foreach my $size (@{$syn->{sizes}})
			{
				$size->{maxLength} and $tsize = $size->{maxLength};
			}
			if ($DataTypesTable{$type})
			{
				$tsize == 0 and $tsize = $DataTypesTable{$type}{size};
				$type = $DataTypesTable{$type}{type};
			}
			$DataTypesTable{$dtype->{name}}{type}=$type;
			$tsize > 0 and $DataTypesTable{$dtype->{name}}{size}=$tsize;
		}
	}
	
	#process nodes
	if ($ind >= $gInd)
	{
		$ind = ($ind - $gInd);
		$i = $ind * $gIndTab;
		@ids[$ind] += 1;
		if ($node->{type} ne "object")
		{
			indprint($i,"<PARAM $ind:$node->{path}>");
			$des=substr($node->{description},0,20);
			indprint($i, "   name=\"$node->{name}\"");
			indprint($i, "   description=\"$des\"");
			indprint($i, "   path=\"$node->{path}\"");
			$type = $node->{type};
			if ($node->{syntax})
			{
				if ($node->{syntax}->{ref})
				{
					$type = $node->{syntax}->{ref};
				}
				elsif ($node->{syntax}->{base})
				{
					$type = $node->{syntax}->{base};
				}
			}
			$tsize = 0;
			if ($node->{syntax}) 
			{
				if ($node->{syntax}->{sizes})
				{
					foreach my $size (@{$node->{syntax}->{sizes}})
					{
						$size->{maxLength} and $tsize = $size->{maxLength}; 
					}
				}
			}
			indprint($i, "   DBGtype=\"$DataTypesTable{$type}\"");
			if ($DataTypesTable{$type} ne "")
			{
				$otype = $type;
				$tsize == 0 and $tsize = $DataTypesTable{$type}{size};
				$type = $DataTypesTable{$type}{type};
				indprint($i, "   type=\"$type\"  (Derived from $otype)");
			}
			
			indprint($i, "   type=\"$type\"");
			indprint($i, "   access=\"$node->{access}\"");
			indprint($i, "   default=\"$node->{default}\"");
			indprint($i, "   version=\"$node->{majorVersion}.$node->{minorVersion}\"");
			$tsize > 0 and indprint($i, "   size:maxLength => $tsize");
		}
		else
		{
			indprint($i,"<OBJECT $ind:$node->{path}>");
		}
	}
}


sub ostruct_init
{
	@ids = (0,0,0,0,0,0,0,0,0,0,0,0,0);  
}


sub ostruct_postpar
{
	my ($node, $ind) = @_;
	if ($ind > $gInd && @ids[$ind] > 0)
	{
		
		$ind = ($ind - $gInd+1);
		$i = $ind * $gIndTab;
		indprint($i, "<ENDPARAM $ind:$node->{path}>");
	}
}


sub ostruct_post
{
	my ($node, $ind) = @_;
	if ($ind > $gInd)
	{
		$ind = ($ind - $gInd);
		$i = $ind * $gIndTab;
		if ($node->{type} eq "object")
		{
			indprint($i, "<ENDOBJECT $ind:$node->{path}>");
			resetid($ind);
		}
	}
}


1;