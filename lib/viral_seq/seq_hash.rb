
module ViralSeq

  # ViralSeq::SeqHash class for operation on multiple sequences.
  # @example read a FASTA sequence file of HIV PR sequences, make alignment, perform the QC location check, filter sequences with stop codons and APOBEC3g/f hypermutations, calculate pairwise diversity, calculate minority cut-off based on Poisson model, and examine for drug resistance mutations.
  #   my_pr_seqhash = ViralSeq::SeqHash.fa('my_pr_fasta_file.fasta')
  #     # new ViralSeq::SeqHash object from a FASTA file
  #   aligned_pr_seqhash = my_pr_seqhash.align
  #     # align with MUSCLE
  #   filtered_seqhash = aligned_pr_seqhash.hiv_seq_qc(2253, 2549, false, :HXB2)
  #     # filter nt sequences with the reference coordinates
  #   filtered_seqhash = aligned_pr_seqhash.stop_codon[1]
  #     # return a new ViralSeq::SeqHash object without stop codons
  #   filtered_seqhash = filtered_seqhash.a3g[1]
  #     # further filter out sequences with A3G hypermutations
  #   filtered_seqhash.pi
  #     # return pairwise diveristy π
  #   cut_off = filtered_seqhash.pm
  #     # return cut-off for minority variants based on Poisson model
  #   filtered_seqhash.sdrm_hiv_pr(cut_off)
  #     # examine for drug resistance mutations for PR region.

  class SeqHash
    # initialize a ViralSeq::SeqHash object
    def initialize (dna_hash = {}, aa_hash = {}, qc_hash = {}, title = "", file = "")
      @dna_hash = dna_hash
      @aa_hash = aa_hash
      @qc_hash = qc_hash
      @title = title
      @file = file
    end

    # @return [Hash] Hash object for :name => :sequence_string pairs
    attr_accessor :dna_hash

    # @return [Hash] Hash object for :name => :amino_acid_sequence_string pairs
    attr_accessor :aa_hash

    # @return [Hash] Hash object for :name => :qc_score_string pairs
    attr_accessor :qc_hash

    # @return [String] the title of the SeqHash object.
    # default as the file basename if SeqHash object is initialized using ::fa or ::fq
    attr_accessor :title

    # @return [String] the file that is used to initialize SeqHash object, if it exists
    attr_accessor :file

    # initialize a new ViralSeq::SeqHash object from a FASTA format sequence file
    # @param infile [String] path to the FASTA format sequence file
    # @return [ViralSeq::SeqHash]
    # @example new ViralSeq::SeqHash object from a FASTA file
    #   ViralSeq::SeqHash.fa('my_fasta_file.fasta')

    def self.new_from_fasta(infile)
      f=File.open(infile,"r")
      return_hash = {}
      name = ""
      while line = f.gets do
        line.tr!("\u0000","")
        next if line == "\n"
        next if line =~ /^\=/
        if line =~ /^\>/
          name = line.chomp
          return_hash[name] = ""
        else
          return_hash[name] += line.chomp.upcase
        end
      end
      f.close
      seq_hash = ViralSeq::SeqHash.new
      seq_hash.dna_hash = return_hash
      seq_hash.title = File.basename(infile,".*")
      seq_hash.file = infile
      return seq_hash
    end # end of ::new_from_fasta

    # initialize a new ViralSeq::SeqHash object from a FASTA format sequence file of amino acid sequences
    # @param infile [String] path to the FASTA format sequence file of aa sequences
    # @return [ViralSeq::SeqHash]

    def self.new_from_aa_fasta(infile)
      f=File.open(infile,"r")
      return_hash = {}
      name = ""
      while line = f.gets do
        line.tr!("\u0000","")
        next if line == "\n"
        next if line =~ /^\=/
        if line =~ /^\>/
          name = line.chomp
          return_hash[name] = ""
        else
          return_hash[name] += line.chomp.upcase
        end
      end
      f.close
      seq_hash = ViralSeq::SeqHash.new
      seq_hash.aa_hash = return_hash
      seq_hash.title = File.basename(infile,".*")
      seq_hash.file = infile
      return seq_hash
    end # end of ::new_from_fasta

    # initialize a new ViralSeq::SeqHash object from a FASTQ format sequence file
    # @param fastq_file [String] path to the FASTA format sequence file
    # @return [ViralSeq::SeqHash]
    # @example new ViralSeq::SeqHash object from a FASTQ file
    #   ViralSeq::SeqHash.fq('my_fastq_file.fastq')

    def self.new_from_fastq(fastq_file)
      count = 0
      sequence_a = []
      quality_a = []
      count_seq = 0

      File.open(fastq_file,'r') do |file|
        file.readlines.collect do |line|
          count +=1
          count_m = count % 4
          if count_m == 1
            line.tr!('@','>')
            sequence_a << line.chomp
            quality_a << line.chomp
            count_seq += 1
          elsif count_m == 2
            sequence_a << line.chomp
          elsif count_m == 0
            quality_a << line.chomp
          end
        end
      end
      sequence_hash = Hash[*sequence_a]
      quality_hash = Hash[*quality_a]

      seq_hash = ViralSeq::SeqHash.new
      seq_hash.dna_hash = sequence_hash
      seq_hash.qc_hash = quality_hash
      seq_hash.title = File.basename(fastq_file,".*")
      seq_hash.file = fastq_file
      return seq_hash
    end # end of ::new_from_fastq

    # initialize a ViralSeq::SeqHash object with an array of sequence strings
    # @param master_tag [String] master tag to put in the sequence names
    # @return [ViralSeq::SeqHash] No @qc_hash, @title will be the master_tag

    def self.new_from_array(seq_array,master_tag = 'seq')
      n = 1
      hash = {}
      seq_array.each do |seq|
        hash[master_tag + "_" + n.to_s] = seq
        n += 1
      end
      seq_hash = ViralSeq::SeqHash.new
      seq_hash.dna_hash = hash
      seq_hash.title = master_tag
      return seq_hash
    end # end of ::new_from_array


    class << self
      alias_method :fa, :new_from_fasta
      alias_method :fq, :new_from_fastq
      alias_method :aa_fa, :new_from_aa_fasta
      alias_method :array, :new_from_array
    end

    # generate sequences in relaxed sequencial phylip format from a ViralSeq::SeqHash object
    # @return [String] relaxed sequencial phylip format in a String object
    # @example convert fasta format to relaxed sequencial phylip format
    #   # my_fasta_file.fasta
    #   #   >seq1
    #   #   ATAAGAACG
    #   #   >seq2
    #   #   ATATGAACG
    #   #   >seq3
    #   #   ATGAGAACG
    #   my_seqhash = ViralSeq::SeqHash.fa(my_fasta_file.fasta)
    #   puts my_seqhash.to_rsphylip
    #     #  3 9
    #     # seq1       ATAAGAACG
    #     # seq2       ATATGAACG
    #     # seq3       ATGAGAACG

    def to_rsphylip
      seqs = self.dna_hash
      outline = "\s" + seqs.size.to_s + "\s" + seqs.values[0].size.to_s + "\n"
      names = seqs.keys
      names.collect!{|n| n.tr(">", "")}
      max_name_l = names.max.size
      max_name_l > 10 ? name_block_l = max_name_l : name_block_l = 10
      seqs.each do |k,v|
        outline += k + "\s" * (name_block_l - k.size + 2) + v.scan(/.{1,10}/).join("\s") + "\n"
      end
      return outline
    end # end of #to_rsphylip

    # translate the DNA sequences in @dna_hash to amino acid sequences. generate value for @aa_hash
    # @param codon_position [Integer] option `0`, `1` or `2`, indicating 1st, 2nd, 3rd reading frames
    # @return [NilClass]
    # @example translate dna sequences from a FASTA format sequence file
    #   # my_fasta_file.fasta
    #   #   >seq1
    #   #   ATAAGAACG
    #   #   >seq2
    #   #   ATATGAACG
    #   #   >seq3
    #   #   ATGAGAACG
    #   my_seqhash = ViralSeq::SeqHash.fa(my_fasta_file.fasta)
    #   my_seqhash.translate
    #   my_seqhash.aa_sequence
    #   => {">seq1"=>"IRT", ">seq2"=>"I*T", ">seq3"=>"MRT"}

    def translate(codon_position = 0)
      seqs = self.dna_hash
      @aa_hash = {}
      seqs.each do |name, seq|
        s = ViralSeq::Sequence.new(name, seq)
        s.translate(codon_position)
        @aa_hash[name] = s.aa_string
      end
      return nil
    end # end of #translate

    # collapse @dna_hash to unique sequence hash.
    # @param tag # the master tag for unique sequences,
    # sequences will be named as (tag + "_" + order(Integer) + "_" + counts(Integer))
    # @return [ViralSeq::SeqHash] new SeqHash object of unique sequence hash
    # @example
    #   dna_hash = {'>seq1' => 'AAAA','>seq2' => 'AAAA', '>seq3' => 'AAAA', '>seq4' => 'CCCC', '>seq5' => 'CCCC', '>seq6' => 'TTTT'} }
    #   a_seq_hash = ViralSeq::SeqHash.new
    #   a_seq_hash.dna_hash = dna_hash
    #   uniq_sequence = a_seq_hash.uniq_dna_hash('master')
    #   => {">master_1_3"=>"AAAA", ">master_2_2"=>"CCCC", ">master_3_1"=>"TTTT"}

    def uniq_dna_hash(tag = "sequence")
      seqs = self.dna_hash
      uni = seqs.values.count_freq
      new_seq = {}
      n = 1
      uni.each do |s,c|
        name = ">" + tag + "_" + n.to_s + "_" + c.to_s
        new_seq[name] = s
        n += 1
      end
      seq_hash = ViralSeq::SeqHash.new(new_seq)
      seq_hash.title = self.title + "_uniq"
      seq_hash.file = self.file
      return seq_hash
    end # end of #uniq_dna_hash

    alias_method :uniq, :uniq_dna_hash

    # given an Array of sequence tags, return a sub ViralSeq::SeqHash object with the sequence tags
    # @param keys [Array] array of sequence tags
    # @return [SeqHash] new SeqHash object with sequences of the input keys

    def sub(keys)
      h1 = {}
      h2 = {}
      h3 = {}

      keys.each do |k|
        dna = self.dna_hash[k]
        next unless dna
        h1[k] = dna
        aa = self.aa_hash[k]
        h2[k] = aa
        qc = self.qc_hash[k]
        h3[k] = qc
      end
      title = self.title
      file = self.file
      ViralSeq::SeqHash.new(h1,h2,h3,title,file)
    end

    # screen for sequences with stop codons.
    # @param (see #translate)
    # @return [Array] of two elements [seqhash_stop_codon, seqhash_no_stop_codon],
    #
    #   # seqhash_stop_codon: ViralSeq::SeqHash object with stop codons
    #   # seqhash_no_stop_codon: ViralSeq::SeqHash object without stop codons
    # @example given a hash of sequences, return a sub-hash with sequences only contains stop codons
    #   my_seqhash = ViralSeq::SeqHash.fa('my_fasta_file.fasta')
    #   my_seqhash.dna_hash
    #   => {">seq1"=>"ATAAGAACG", ">seq2"=>"ATATGAACG", ">seq3"=>"ATGAGAACG", ">seq4"=>"TATTAGACG", ">seq5"=>"CGCTGAACG"}
    #   stop_codon_seqhash = my_seqhash.stop_codon[0]
    #   stop_codon_seqhash.dna_hash
    #   => {">seq2"=>"ATATGAACG", ">seq4"=>"TATTAGACG", ">seq5"=>"CGCTGAACG"}
    #   stop_codon_seqhash.aa_hash
    #   => {">seq2"=>"I*T", ">seq4"=>"Y*T", ">seq5"=>"R*T"}
    #   stop_codon_seqhash.title
    #   => "my_fasta_file_stop"
    #   filtered_seqhash = my_seqhash.stop_codon[1]
    #   filtered_seqhash.aa_hash
    #   {">seq1"=>"IRT", ">seq3"=>"MRT"}

    def stop_codon(codon_position = 0)
      self.translate(codon_position)
      keys = []
      self.aa_hash.each do |k,v|
        keys << k if v.include?('*')
      end
      seqhash1 = self.sub(keys)
      seqhash1.title = self.title + "_stop"
      keys2 = self.aa_hash.keys - keys
      seqhash2 = self.sub(keys2)
      return [seqhash1, seqhash2]
    end #end of #stop_codon


    # create one consensus sequence from @dna_hash with an optional majority cut-off for mixed bases.
    # @param cutoff [Float] majority cut-off for calling consensus bases. defult at simple majority (0.5), position with 15% "A" and 85% "G" will be called as "G" with 20% cut-off and as "R" with 10% cut-off.
    # @return [String] consensus sequence
    # @example consensus sequence from an array of sequences.
    #   seq_array = %w{ ATTTTTTTTT
    #                   AATTTTTTTT
    #                   AAATTTTTTT
    #                   AAAATTTTTT
    #                   AAAAATTTTT
    #                   AAAAAATTTT
    #                   AAAAAAATTT
    #                   AAAAAAAATT
    #                   AAAAAAAAAT
    #                   AAAAAAAAAA }
    #   my_seqhash = ViralSeq::SeqHash.array(seq_array)
    #   my_seqhash.consensus
    #   => 'AAAAAWTTTT'
    #   my_seqhash.consensus(0.7)
    #   => 'AAAANNNTTT'

    def consensus(cutoff = 0.5)
      seq_array = self.dna_hash.values
      seq_length = seq_array[0].size
      seq_size = seq_array.size
      consensus_seq = ""
      (0..(seq_length - 1)).each do |position|
        all_base = []
        seq_array.each do |seq|
          all_base << seq[position]
        end
        base_count = all_base.count_freq
        max_base_list = []

        base_count.each do |k,v|
          if v/seq_size.to_f >= cutoff
            max_base_list << k
          end
        end
        consensus_seq += call_consensus_base(max_base_list)
      end
      return consensus_seq
    end #end of #consensus

    # function to determine if the sequences have APOBEC3g/f hypermutation.
    #   # APOBEC3G/F pattern: GRD -> ARD
    #   # control pattern: G[YN|RC] -> A[YN|RC]
    #   # use the sample consensus to determine potential a3g sites
    #   # Two criteria to identify hypermutation
    #   # 1. Fisher's exact test on the frequencies of G to A mutation at A3G positons vs. non-A3G positions
    #   # 2. Poisson distribution of G to A mutations at A3G positions, outliers sequences
    #   # note:  criteria 2 only applies on a sequence file containing more than 20 sequences,
    #   #        b/c Poisson model does not do well on small sample size.
    # @return [Array] three values.
    #   first value, `array[0]`: a ViralSeq:SeqHash object for sequences with hypermutations
    #   second value, `array[1]`: a ViralSeq:SeqHash object for sequences without hypermutations
    #   third value, `array[2]`: a two-demensional array `[[a,b], [c,d]]` for statistic_info, including the following information,
    #     # sequence tag
    #     # G to A mutation numbers at potential a3g positions
    #     # total potential a3g G positions
    #     # G to A mutation numbers at non a3g positions
    #     # total non a3g G positions
    #     # a3g G to A mutation rate / non-a3g G to A mutation rate
    #     # Fishers Exact P-value
    # @example identify apobec3gf mutations from a sequence fasta file
    #   my_seqhash = ViralSeq::SeqHash.fa('spec/sample_files/sample_a3g_sequence1.fasta')
    #   hypermut = my_seqhash.a3g
    #   hypermut[0].dna_hash.keys
    #   => [">Seq7", ">Seq14"]
    #   hypermut[1].dna_hash.keys
    #   => [">Seq1", ">Seq2", ">Seq5"]
    #   hypermut[2]
    #   => [[">Seq7", 23, 68, 1, 54, 18.26, 4.308329383112348e-06], [">Seq14", 45, 68, 9, 54, 3.97, 5.2143571971582974e-08]]
    #
    # @example identify apobec3gf mutations from another sequence fasta file
    #   my_seqhash = ViralSeq::SeqHash.fa('spec/sample_files/sample_a3g_sequence2.fasta')
    #   hypermut = my_seqhash.a3g
    #   hypermut[2]
    #   => [[">CTAACACTCA_134_a3g-sample2", 4, 35, 0, 51, Infinity, 0.02465676660128911], [">ATAGTGCCCA_60_a3g-sample2", 4, 35, 1, 51, 5.83, 0.1534487353839561]]
    #   # notice sequence ">ATAGTGCCCA_60_a3g-sample2" has a p value at 0.15, greater than 0.05,
    #   # but it is still called as hypermutation sequence b/c it's Poisson outlier sequence.
    # @see https://www.hiv.lanl.gov/content/sequence/HYPERMUT/hypermut.html LANL Hypermut

    def a3g_hypermut
      # mut_hash number of apobec3g/f mutations per sequence
      mut_hash = {}
      hm_hash = {}
      out_hash = {}

      # total G->A mutations at apobec3g/f positions.
      total = 0

      # make consensus sequence for the input sequence hash
      ref = self.consensus

      # obtain apobec3g positions and control positions
      apobec = apobec3gf(ref)
      mut = apobec[0]
      control = apobec[1]

      self.dna_hash.each do |k,v|
        a = 0 # muts
        b = 0 # potential mut sites
        c = 0 # control muts
        d = 0 # potenrial controls
        mut.each do |n|
          next if v[n] == "-"
          if v[n] == "A"
            a += 1
            b += 1
          else
            b += 1
          end
        end
        mut_hash[k] = a
        total += a

        control.each do |n|
          next if v[n] == "-"
          if v[n] == "A"
            c += 1
            d += 1
          else
            d += 1
          end
        end
        rr = (a/b.to_f)/(c/d.to_f)

        t1 = b - a
        t2 = d - c

        fet = ViralSeq::Rubystats::FishersExactTest.new
        fisher = fet.calculate(t1,t2,a,c)
        perc = fisher[:twotail]
        info = [k, a, b, c, d, rr.round(2), perc]
        out_hash[k] = info
        if perc < 0.05
          hm_hash[k] = info
        end
      end

      if self.dna_hash.size > 20
        rate = total.to_f/(self.dna_hash.size)
        count_mut = mut_hash.values.count_freq
        maxi_count = count_mut.values.max
        poisson_hash = ViralSeq::Math::PoissonDist.new(rate,maxi_count).poisson_hash
        cut_off = 0
        poisson_hash.each do |k,v|
          cal = self.dna_hash.size * v
          obs = count_mut[k]
          if obs >= 20 * cal
            cut_off = k
            break
          elsif k == maxi_count
            cut_off = maxi_count
          end
        end
        mut_hash.each do |k,v|
          if v > cut_off
            hm_hash[k] = out_hash[k]
          end
        end
      end
      hm_seq_hash = ViralSeq::SeqHash.new
      hm_hash.each do |k,_v|
        hm_seq_hash.dna_hash[k] = self.dna_hash[k]
      end
      hm_seq_hash.title = self.title + "_hypermut"
      hm_seq_hash.file = self.file
      filtered_seq_hash = self.sub(self.dna_hash.keys - hm_hash.keys)
      return [hm_seq_hash, filtered_seq_hash, hm_hash.values]
    end #end of #a3g_hypermut

    alias_method :a3g, :a3g_hypermut

    # Define Poission cut-off for minority variants.
    # @see https://www.ncbi.nlm.nih.gov/pubmed/26041299 Ref: Zhou, et al. J Virol 2015
    # @param error_rate [Float] estimated sequencing error rate
    # @param fold_cutoff [Integer] a fold cut-off to determine poisson minority cut-off. default = 20. i.e. <5% mutations from random methods error.
    # @return [Integer] a cut-off for minority variants (>=).
    # @example obtain Poisson minority cut-off from the example sequence FASTA file.
    #   my_seqhash = ViralSeq::SeqHash.fa('spec/sample_files/sample_sequence_for_poisson.fasta')
    #   my_seqhash.pm
    #   => 2 # means that mutations appear at least 2 times are very likely to be a true mutation instead of random methods errors.

    def poisson_minority_cutoff(error_rate = 0.0001, fold_cutoff = 20)
      sequences = self.dna_hash.values
      if sequences.size == 0
        return 0
      else
        cut_off = 1
        l = sequences[0].size
        rate = sequences.size * error_rate
        count_mut = variant_for_poisson(sequences)
        max_count = count_mut.keys.max
        poisson_hash = ViralSeq::Math::PoissonDist.new(rate, max_count).poisson_hash

        poisson_hash.each do |k,v|
          cal = l * v
          obs = count_mut[k] ? count_mut[k] : 0
          if obs >= fold_cutoff * cal
            cut_off = k
            break
          end
        end
        return cut_off
      end
    end # end of #poisson_minority_cutoff

    alias_method :pm, :poisson_minority_cutoff


    # align the @dna_hash sequences, return a new ViralSeq::SeqHash object with aligned @dna_hash using MUSCLE
    # @param path_to_muscle [String], path to MUSCLE excutable. if not provided (as default), it will use RubyGem::MuscleBio
    # @return [SeqHash] new SeqHash object of the aligned @dna_hash, the title has "_aligned"

    def align(path_to_muscle = false)
      seq_hash = self.dna_hash
      if self.file.size > 0
        temp_dir = File.dirname(self.file)
      else
        temp_dir=File.dirname($0)
      end

      temp_file = temp_dir + "/_temp_muscle_in"
      temp_aln = temp_dir + "/_temp_muscle_aln"
      File.open(temp_file, 'w'){|f| seq_hash.each {|k,v| f.puts k; f.puts v}}
      if path_to_muscle
        unless ViralSeq.check_muscle?(path_to_muscle)
          File.unlink(temp_file)
          return nil
        end
        print `#{path_to_muscle} -in #{temp_file} -out #{temp_aln} -quiet`
      else
        MuscleBio.run("muscle -in #{temp_file} -out #{temp_aln} -quiet")
      end
      out_seq_hash = ViralSeq::SeqHash.fa(temp_aln)
      out_seq_hash.title = self.title + "_aligned"
      out_seq_hash.file = self.file
      File.unlink(temp_file)
      File.unlink(temp_aln)
      return out_seq_hash
    end # end of align

    # calculate Shannon's entropy, Euler's number as the base of logarithm
    # @see https://en.wikipedia.org/wiki/Entropy_(information_theory) Entropy(Wikipedia)
    # @param option [Symbol] the sequence type `:nt` or `:aa`
    # @return [Hash] entropy score at each position in the alignment :position => :entropy ,
    #   # position starts at 1.
    # @example caculate entropy from the example file
    #   sequence_file = 'spec/sample_files/sample_sequence_alignment_for_entropy.fasta'
    #   sequence_hash = ViralSeq::SeqHash.aa_fa(sequence_file)
    #   entropy_hash = sequence_hash.shannons_entropy(:aa)
    #   entropy_hash[3]
    #   => 0.0
    #   entropy_hash[14].round(3)
    #   => 0.639
    #   # This example is the sample input of LANL Entropy-One
    #   # https://www.hiv.lanl.gov/content/sequence/ENTROPY/entropy_one.html?sample_input=1

    def shannons_entropy(option = :nt)
      sequences = if option == :aa
                    self.aa_hash.values
                  else
                    self.dna_hash.values
                  end
      entropy_hash = {}
      seq_l = sequences[0].size
      (0..(seq_l - 1)).each do |position|
        element = []
        sequences.each do |seq|
          element << seq[position]
        end
        entropy = 0
        element.delete('*')
        element_size = element.size
        element.count_freq.each do |_k,v|
          p = v/element_size.to_f
          entropy += (-p * ::Math.log(p))
        end
        entropy_hash[(position + 1)] = entropy
      end
      return entropy_hash
    end # end of shannons_entropy

    # Function to calculate nucleotide diversity π, for nt sequence only
    # @see https://en.wikipedia.org/wiki/Nucleotide_diversity Nucleotide Diversity (Wikipedia)
    # @return [Float] nucleotide diversity π
    # @example calculate π
    #   sequences = %w{ AAGGCCTT ATGGCCTT AAGGCGTT AAGGCCTT AACGCCTT AAGGCCAT }
    #   my_seqhash = ViralSeq::SeqHash.array(sequences)
    #   my_seqhash.pi
    #   => 0.16667

    def nucleotide_pi
      sequences = self.dna_hash.values
      seq_length = sequences[0].size - 1
      nt_position_hash = {}
      (0..seq_length).each do |n|
        nt_position_hash[n] = []
        sequences.each do |s|
          nt_position_hash[n] << s[n]
        end
      end
      diver = 0
      com = 0
      nt_position_hash.each do |_p,nt|
        nt.delete_if {|n| n =~ /[^A|^C|^G|^T]/}
        next if nt.size == 1
        nt_count = nt.count_freq
        combination = (nt.size)*(nt.size - 1)/2
        com += combination
        a = nt_count["A"]
        c = nt_count["C"]
        t = nt_count["T"]
        g = nt_count["G"]
        div = a*c + a*t + a*g + c*t + c*g + t*g
        diver += div
      end
      pi = (diver/com.to_f).round(5)
      return pi
    end # end of #pi

    alias_method :pi, :nucleotide_pi

    # TN93 distance functionl, tabulate pairwise comparison of sequence pairs in a sequence alignment,
    # nt sequence only
    # @return [Hash] pairwise distance table in Hash object {:diff => :freq, ... }
    #   # Note: :diff in different positions (Integer), not percentage.
    # @example calculate TN93 distribution
    #   sequences = %w{ AAGGCCTT ATGGCCTT AAGGCGTT AAGGCCTT AACGCCTT AAGGCCAT }
    #   my_seqhash = ViralSeq::SeqHash.array(sequences)
    #   my_seqhash.tn93
    #   => {0=>1, 1=>8, 2=>6}

    def tn93
      sequences = self.dna_hash.values
      diff = []
      seq_hash = sequences.count_freq
      seq_hash.values.each do |v|
        comb = v * (v - 1) / 2
        comb.times {diff << 0}
      end

      seq_hash.keys.combination(2).to_a.each do |pair|
        s1 = pair[0]
        s2 = pair[1]
        diff_temp = s1.compare_with(s2)
        comb = seq_hash[s1] * seq_hash[s2]
        comb.times {diff << diff_temp}
      end

      count_diff = diff.count_freq
      out_hash = Hash.new(0)
      Hash[count_diff.sort_by{|k,_v|k}].each do |k,v|
        out_hash[k] = v
      end
      return out_hash
    end # end of #tn93

    # quality check for HIV sequences based on ViralSeq::Sequence#locator, check if sequences are in the target range
    # @param start_nt [Integer,Range,Array] start nt position(s) on the refernce genome, can be single number (Integer) or a range of Integers (Range), or an Array
    # @param end_nt [Integer,Range,Array] end nt position(s) on the refernce genome,can be single number (Integer) or a range of Integers (Range), or an Array
    # @param indel [Boolean] allow indels or not, `ture` or `false`
    # @param ref_option [Symbol], name of reference genomes, options are `:HXB2`, `:NL43`, `:MAC239`
    # @param path_to_muscle [String], path to the muscle executable, if not provided, use MuscleBio to run Muscle
    # @return [ViralSeq::SeqHash] a new ViralSeq::SeqHash object with only the sequences that meet the QC criterias
    # @example QC for sequences in a FASTA files
    #   my_seqhash = ViralSeq::SeqHash.fa('spec/sample_files/sample_seq.fasta')
    #   filtered_seqhash = my_seqhash.hiv_seq_qc([4384,4386], 4750..4752, false, :HXB2)
    #   my_seqhash.dna_hash.size
    #   => 6
    #   filtered_seqhash.dna_hash.size
    #   => 4

    def hiv_seq_qc(start_nt, end_nt, indel=true, ref_option = :HXB2, path_to_muscle = false)
      start_nt = start_nt..start_nt if start_nt.is_a?(Integer)
      end_nt = end_nt..end_nt if end_nt.is_a?(Integer)
      seq_hash = self.dna_hash.dup
      seq_hash_unique = seq_hash.values.uniq
      seq_hash_unique_pass = []

      seq_hash_unique.each do |seq|
        loc = ViralSeq::Sequence.new('', seq).locator(ref_option, path_to_muscle)
        if start_nt.include?(loc[0]) && end_nt.include?(loc[1])
          if indel
            seq_hash_unique_pass << seq
          elsif loc[3] == false
            seq_hash_unique_pass << seq
          end
        end
      end
      seq_pass = []
      seq_hash_unique_pass.each do |seq|
        seq_hash.each do |seq_name, orginal_seq|
          if orginal_seq == seq
            seq_pass << seq_name
            seq_hash.delete(seq_name)
          end
        end
      end
      self.sub(seq_pass)
    end # end of #hiv_seq_qc

    # sequence locator for SeqHash object, resembling HIV Sequence Locator from LANL
    # @param ref_option [Symbol], name of reference genomes, options are `:HXB2`, `:NL43`, `:MAC239`
    # @return [Array] two dimensional array `[[],[],[],...]` for each sequence, including the following information:
    #
    #     title of the SeqHash object (String)
    #
    #     sequence taxa (String)
    #
    #     start_location (Integer)
    #
    #     end_location (Integer)
    #
    #     percentage_of_similarity_to_reference_sequence (Float)
    #
    #     containing_indel? (Boolean)
    #
    #     direction ('forward' or 'reverse')
    #
    #     aligned_input_sequence (String)
    #
    #     aligned_reference_sequence (String)
    # @see https://www.hiv.lanl.gov/content/sequence/LOCATE/locate.html LANL Sequence Locator
    def sequence_locator(ref_option = :HXB2)
      out_array = []
      dna_seq = self.dna_hash
      title = self.title

      uniq_dna = dna_seq.uniq_hash

      uniq_dna.each do |seq,names|
        s = ViralSeq::Sequence.new('',seq)
        loc1 = s.locator(ref_option)
        s.rc!
        loc2 = s.locator(ref_option)
        loc1[2] >= loc2[2] ? (direction = :+; loc = loc1): (direction = :-; loc = loc2)
    
        names.each do |name|
          out_array << ([title, name, ref_option.to_s, direction.to_s] + loc)
        end
      end
      return out_array
    end # end of locator
    alias_method :loc, :sequence_locator

    # Remove squences with residual offspring Primer IDs.
    #   Compare PID with sequences which have identical sequences.
    #   PIDs differ by 1 base will be recognized. If PID1 is x time (cutoff) greater than PID2, PID2 will be disgarded.
    #     each sequence tag starting with ">" and the Primer ID sequence
    #     followed by the number of Primer ID appeared in the raw sequence
    #     the information sections in the tags are separated by underscore "_"
    #     example sequence tag: >AGGCGTAGA_32_sample1_RT
    # @param cutoff [Integer] the fold cut-off to remove the potential residual offspring Primer IDs
    # @return [ViralSeq::SeqHash] a new SeqHash object without sqeuences containing residual offspring Primer ID

    def filter_similar_pid(cutoff = 10)
      seq = self.dna_hash.dup
      uni_seq = seq.values.uniq
      uni_seq_pid = {}
      uni_seq.each do |k|
        seq.each do |name,s|
          name = name[1..-1]
          if k == s
            if uni_seq_pid[k]
              uni_seq_pid[k] << [name.split("_")[0],name.split("_")[1]]
            else
              uni_seq_pid[k] = []
              uni_seq_pid[k] << [name.split("_")[0],name.split("_")[1]]
            end
          end
        end
      end

      dup_pid = []
      uni_seq_pid.values.each do |v|
        next if v.size == 1
        pid_hash = Hash[v]
        list = pid_hash.keys
        list2 = Array.new(list)
        pairs = []

        list.each do |k|
          list2.delete(k)
          list2.each do |k1|
            pairs << [k,k1]
          end
        end

        pairs.each do |p|
          pid1 = p[0]
          pid2 = p[1]
          if pid1.compare_with(pid2) <= 1
            n1 = pid_hash[pid1].to_i
            n2 = pid_hash[pid2].to_i
            if n1 >= cutoff * n2
              dup_pid << pid2
            elsif n2 >= cutoff * n1
              dup_pid << pid1
            end
          end
        end
      end

      new_seq = {}
      seq.each do |name,s|
        pid = name.split("_")[0][1..-1]
        unless dup_pid.include?(pid)
          new_seq[name] = s
        end
      end
      self.sub(new_seq.keys)
    end # end of #filter_similar_pid

    # Collapse sequences by difference cut-offs. Suggesting aligning before using this function.
    # @param cutoff [Integer] nt base differences. collapse sequences within [cutoff] differences
    # @return [ViralSeq::SeqHash] a new SeqHash object of collapsed sequences

    def collapse(cutoff=1)
      seq_array = self.dna_hash.values
      new_seq_freq = {}
      seq_freq = seq_array.count_freq
      if seq_freq.size == 1
        new_seq_freq = seq_freq
      else
        uniq_seq = seq_freq.keys
        unique_seq_pair = uniq_seq.combination(2)
        dupli_seq = []
        unique_seq_pair.each do |pair|
          seq1 = pair[0]
          seq2 = pair[1]
          diff = seq1.compare_with(seq2)
          if diff <= cutoff
            freq1 = seq_freq[seq1]
            freq2 = seq_freq[seq2]
            freq1 >= freq2 ? dupli_seq << seq2 : dupli_seq << seq1
          end
        end

        seq_freq.each do |seq,freq|
          unless dupli_seq.include?(seq)
            new_seq_freq[seq] = freq
          end
        end
      end
      seqhash = ViralSeq::SeqHash.new
      n = 1
      new_seq_freq.each do |seq,freq|
        name = ">seq_" + n.to_s + '_' + freq.to_s
        seqhash.dna_hash[name] = seq
        n += 1
      end
      return seqhash
    end # end of #collapse

    # gap strip from a sequence alignment, all positions that contains gaps ('-') will be removed
    # @param option [Symbol] sequence options for `:nt` or `:aa`
    # @return [ViralSeq::SeqHash] a new SeqHash object containing nt or aa sequences without gaps
    # @example gap strip for an array of sequences
    #   array = ["AACCGGTT", "A-CCGGTT", "AAC-GGTT", "AACCG-TT", "AACCGGT-"]
    #   array = { AACCGGTT
    #             A-CCGGTT
    #             AAC-GGTT
    #             AACCG-TT
    #             AACCGGT- }
    #   my_seqhash = ViralSeq::SeqHash.array(array)
    #   puts my_seqhash.gap_strip.dna_hash.values
    #     ACGT
    #     ACGT
    #     ACGT
    #     ACGT
    #     ACGT

    def gap_strip(option = :nt)
      if option == :nt
        sequence_alignment = self.dna_hash
      elsif option == :aa
        sequence_alignment = self.aa_hash
      else
        raise "Option `#{option}` not recognized"
      end

      new_seq = {}
      seq_size = sequence_alignment.values[0].size
      seq_matrix = {}
      (0..(seq_size - 1)).each do |p|
        seq_matrix[p] = []
        sequence_alignment.values.each do |s|
          seq_matrix[p] << s[p]
        end
      end

      seq_matrix.delete_if do |_p, list|
        list.include?("-")
      end

      sequence_alignment.each do |n,s|
        new_s = ""
        seq_matrix.keys.each {|p| new_s += s[p]}
        new_seq[n] = new_s
      end
      new_seq_hash = ViralSeq::SeqHash.new
      if option == :nt
        new_seq_hash.dna_hash = new_seq
        new_seq_hash.aa_hash = self.aa_hash
      elsif option == :aa
        new_seq_hash.dna_hash = self.dna_hash
        new_seq_hash.aa_hash = new_seq
      end
      new_seq_hash.qc_hash = self.qc_hash
      new_seq_hash.title = self.title + "_strip"
      new_seq_hash.file = self.file
      return new_seq_hash
    end

    # gap strip from a sequence alignment at both ends, only positions at the ends that contains gaps ('-') will be removed.
    # @param (see #gap_strip)
    # @return [ViralSeq::SeqHash] a new SeqHash object containing nt or aa sequences without gaps at the ends
    # @example gap strip for an array of sequences only at the ends
    #   array = ["AACCGGTT", "A-CCGGTT", "AAC-GGTT", "AACCG-TT", "AACCGGT-"]
    #   array = { AACCGGTT
    #             A-CCGGTT
    #             AAC-GGTT
    #             AACCG-TT
    #             AACCGGT- }
    #   my_seqhash = ViralSeq::SeqHash.array(array)
    #   puts my_seqhash.gap_strip_ends.dna_hash.values
    #     AACCGGT
    #     A-CCGGT
    #     AAC-GGT
    #     AACCG-T
    #     AACCGGT

    def gap_strip_ends(option = :nt)
      if option == :nt
        sequence_alignment = self.dna_hash
      elsif option == :aa
        sequence_alignment = self.aa_hash
      else
        raise "Option #{option} not recognized"
      end
      new_seq = {}
      seq_size = sequence_alignment.values[0].size
      seq_matrix = {}
      (0..(seq_size - 1)).each do |p|
        seq_matrix[p] = []
        sequence_alignment.values.each do |s|
          seq_matrix[p] << s[p]
        end
      end
      n1 = 0
      n2 = 0
      seq_matrix.each do |_p, list|
        if list.include?("-")
          n1 += 1
        else
          break
        end
      end

      seq_matrix.keys.reverse.each do |p|
        list = seq_matrix[p]
        if list.include?("-")
          n2 += 1
        else
          break
        end
      end

      sequence_alignment.each do |n,s|
        new_s = s[n1..(- n2 - 1)]
        new_seq[n] = new_s
      end
      new_seq_hash = ViralSeq::SeqHash.new
      if option == :nt
        new_seq_hash.dna_hash = new_seq
        new_seq_hash.aa_hash = self.aa_hash
      elsif option == :aa
        new_seq_hash.dna_hash = self.dna_hash
        new_seq_hash.aa_hash = new_seq
      end
      new_seq_hash.qc_hash = self.qc_hash
      new_seq_hash.title = self.title + "_strip"
      new_seq_hash.file = self.file
      return new_seq_hash
    end





    # start of private functions
    private

    # APOBEC3G/F mutation position identification,
    # APOBEC3G/F pattern: GRD -> ARD,
    # control pattern: G[YN|RC] -> A[YN|RC],
    def apobec3gf(seq = '')
      seq.tr!("-", "")
      seq_length = seq.size
      apobec_position = []
      control_position = []
      (0..(seq_length - 3)).each do |n|
        tri_base = seq[n,3]
        if tri_base =~ /G[A|G][A|G|T]/
          apobec_position << n
        elsif seq[n] == "G"
          control_position << n
        end
      end
      return [apobec_position,control_position]
    end # end of #apobec3gf

    # call consensus nucleotide, used by #consensus
    def call_consensus_base(base_array)
      if base_array.size == 1
         base_array[0]
      elsif base_array.size == 2
        case base_array.sort!
        when ["A","T"]
          "W"
        when ["C","G"]
          "S"
        when ["A","C"]
          "M"
        when ["G","T"]
           "K"
        when ["A","G"]
           "R"
        when ["C","T"]
           "Y"
        else
           "N"
        end
      elsif base_array.size == 3
        case base_array.sort!
        when ["C","G","T"]
           "B"
        when ["A","G","T"]
           "D"
        when ["A","C","T"]
           "H"
        when ["A","C","G"]
           "V"
        else
           "N"
        end
      else
         "N"
      end
    end # end of #call_consensus_base

    # Input sequence array. output Variant distribution for Poisson cut-off
    def variant_for_poisson(seq)
      seq_size = seq.size
      l = seq[0].size - 1
      var = []
      (0..l).to_a.each do |pos|
        nt = []
        seq.each do |s|
          nt << s[pos]
        end
        count_nt = nt.count_freq
        v = seq_size - count_nt.values.max
        var << v
      end
      var_count = var.count_freq
      var_count.sort_by{|key,_value|key}.to_h
    end # end of #varaint_for_poisson

  end # end of SeqHash

end # end of ViralSeq
